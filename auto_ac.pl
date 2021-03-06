#!/usr/bin/perl

# our laws are broken in a way that we have to pay high prices if we take electricity from the grid
# but get payed much less if we give energy back.
# so, i use as much energy as possible in the ACs to have a nice
# cool house once I come home from work and the sun is alredy low or gone.
# better than giving it away more or less for free.
#
# this turns your ACs on and off automatically.
# it factors in:
# - room air temperature
# - room floor/wall temperature
# - maximum day temperature forecast
# - available power surplus from the aolar panels

use strict;
use warnings;
use 5.020;
use Data::Dumper;

use JSON;
use DBM::Deep;
use File::Slurp qw(slurp);

use POSIX;
use List::Util qw(sum);
use Time::Out qw(timeout) ;
use PID::File;


use lib qw( lib /usr/local/lib/home_automation/perl );
use Net::Pushover;
use qmel;
use get_weather;
use config;
use Net::MQTT::Simple;

use PID::File;
 
my $pid_file = PID::File->new;
$pid_file->file( '/tmp/auto_ac.pid' );
 
exit if $pid_file->running;
$pid_file->create or die 'could not create pid-file';
$pid_file->guard;
 


my $cron_mode = $ARGV[0];
my @title = ('AC');
my @facts;

my $config = config->new();

my $push = Net::Pushover->new(
  token => $config->{keys}{pushover_app},
  user  => $config->{keys}{pushover_user},
);

my $mqtt = Net::MQTT::Simple->new( $config->{host}{mqtt} );

my $weather = get_weather->new( max_age => ( 2 * 3600 ) );    # seconds

$Data::Dumper::Sortkeys = 1;

my $add_surplus    = $config->{ac}{add_surplus};              # Watts
my $remove_surplus = $config->{ac}{remove_surplus};           # Watts
my $high_surplus   = $config->{ac}{high_surplus};             # Watts

my $demand_on_threshold  = 1;
my $demand_off_threshold = -1;
my $overshoot            = 1;                                 # °C to set the AC below target. increase if conditions require

my $high_power_available = 0;

my %rooms = %{ $config->{ac}{rooms} };

my $qmel = qmel->new( rooms => \%rooms); 




my $heater = decode_json( slurp $config->{files}{heater_json_file} );
my $winter =
	   $weather->{cache}{max_temp_today} <= $config->{ac}{min_day_temp}
	|| $weather->{cache}{min_temp_today} <=
	$config->{ac}{min_night_temp};    # in spring, the sun is strong and can heat up the rooms but it still gets cold at night.
my $hot_day = $weather->{cache}{max_temp_today} > $config->{ac}{hot_day_temp};
my $super_hot_day = $weather->{cache}{max_temp_today} > $config->{ac}{super_hot_day_temp};


$overshoot++ if $super_hot_day;

my @datapoints;
my $db = DBM::Deep->new(
	file => $config->{files}{power_balance_file},
	type => DBM::Deep->TYPE_ARRAY
);
$db->lock_shared();

for my $i ( reverse -1 * scalar @$db .. -1 ) {    # perhaps reverse the order all together to get rid of this abomination
	                                              # say "$i, $db->[$i]{time} - $db->[$i]{power}";
	push @datapoints, $db->[$i]{power} if $db->[$i]{time} > time - 1800;
}

$db->unlock();
my $power_budget = 0;
if ( @datapoints > 8 ) {
	@datapoints   = sort @datapoints;
	$power_budget = median(@datapoints);
}
else {
	warn "not enough data points for power budget calculation!";
	exit;
}

say "We have $power_budget W of available solar power";

my $status =<<STATUS;
max temp: $weather->{cache}{max_temp_today} ($config->{ac}{min_day_temp} / $config->{ac}{hot_day_temp} / $config->{ac}{super_hot_day_temp})
power: $power_budget
overshoot: $overshoot
STATUS

push @facts, "Power: $power_budget W",
	"max temp: $weather->{cache}{max_temp_today} ($config->{ac}{min_day_temp} / $config->{ac}{hot_day_temp} / $config->{ac}{super_hot_day_temp})",
	"overshoot: $overshoot";


# my $now = $yr->location_forecast->now;
# say "It's " . $now->temperature->celsius . "°C outside.";
# say "Weather status: " . $now->precipitation->symbol->text;

$qmel->login();
my $stuff = $qmel->get_state(); # required to prep the object
my $d;
# warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$stuff], ['stuff']);
# $qmel->print_config();
#$d = $qmel->get_device_state('Wohnzimmer');
# $d = $qmel->set_ac( 'Wohnzimmer', { Power => 1, SetTemperature => 21} );
#warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$d], ['d']);

my ( @off, @on );
for my $ac ( keys %rooms ) {
	my %ac = ();

	# might change weight to an offset, not a factor.
	say "$ac: room: $heater->{rooms}{lc($ac)}{room}; floor: $heater->{rooms}{lc($ac)}{floor}; target: $rooms{$ac}{target}";
	my $demand_on  = ( $heater->{rooms}{ lc($ac) }{room} - $rooms{$ac}{target} ) * $rooms{$ac}{weight};
	my $demand_off = ( $heater->{rooms}{ lc($ac) }{floor} - $rooms{$ac}{target} );
	$demand_off = ( $demand_off < 0 ? $demand_off / $rooms{$ac}{weight} : $demand_off * $rooms{$ac}{weight} );
	$ac{name} = $ac;
	$ac{demand_on}  = $demand_on;
	$ac{demand_off} = $demand_off;

	my $state = $qmel->get_device_state($ac);
	if ( AC_COOL == $state->{OperationMode} && 0 == $state->{SetFanSpeed} ) {
		say "$ac is auto";
		if ( $state->{Power} ) {
			push @on, \%ac;
		}
		else {
			push @off, \%ac;
		}
	}
	else {
		say "$ac is not auto $state->{OperationMode}";
	}
}

# get AC lockouts from MQTT
my %missing_rooms = (map {$_ => 1} keys %rooms);
my %room_lockout;

# do this at the latest possible way because this scipt 
# takes ages to load and run due to slow weather module and api calls.
# so, if someone triggered a lockout change accidentally leave
# some time to get the latest value of lockouts.
timeout 3 => sub {

	# your code goes were and will be interrupted if it runs
	# for more than $nb_secs seconds.
	$mqtt->run(
		"ac/lockout/+" => sub {
			my ( $full_topic, $message ) = @_;
			my $room = $full_topic;
			$room =~ s{^.*/}{};
			if ( exists $missing_rooms{$room} ) {
				say "Lockout $room = $message";
				$room_lockout{$room} = $message;
				delete $missing_rooms{$room};
			}
			$mqtt->{stop_loop} = 1 unless keys %missing_rooms;
		},
	);
};
if ($@) {

	# operation timed-out
	warn "command response timed out, missing rooms: " . join ' ', keys %missing_rooms;
}
$mqtt->unsubscribe("ac/lockout/+");

@off = sort { $b->{demand_on} <=> $a->{demand_on} } grep { ! $room_lockout{ $_->{name} } } @off;
@on  = sort { $a->{demand_off} <=> $b->{demand_off} } @on;

say __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\@off], ['off']);
say __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\@on], ['on']);
my @actions;
if ( $power_budget > $high_surplus) {
	$demand_on_threshold = 0.5;
	$demand_off_threshold = -2; # effectively, no auto off
	$high_power_available = 1;
	push @facts, 'high_power';
}
# turn off devices with lockout, others remain in @on
@on = grep {
	if ( $room_lockout{ $_->{name} } ) {
		$_->{power}  = 0;
		$_->{reason} = 'lockout';
		push @actions, $_;
	}
	else {$_}
} @on;

if (0) {
}
elsif(0 && $power_budget < 0 && @on ) {
	# no power left, remove all running devices
	# disable for now
	for my $device (@on) {
		$device->{power}  = 0;
		$device->{reason} = 'no power';
		push @actions, $device;
		shift @on;
	}
}
elsif ( $power_budget < $remove_surplus && @on ) {

	# power running low, remove device with the lowest demand_off
	my $device = shift @on;
	$device->{power} = 0;
	$device->{reason} = 'low power';
	push @actions, $device;
	
}
elsif ( $power_budget > $add_surplus && @off ) {

	# we've got the power
	# power on device with the highest demand_on
	# but only if the demand is high enough, we don't want AC in the winter
	if ( ( $high_power_available && $hot_day ) || ( !$winter && $off[0]{demand_on} > $demand_on_threshold ) ) {
		my $device = shift @off;
		$device->{power} = 1;
		$device->{reason} = 'high power';
		push @actions, $device;
	}

	# in case there is nothing to turn on, check if something has cooled down enough and turn that off.
	elsif ( @on && $on[0]{demand_off} < $demand_off_threshold ) {

		# turn off ac that has overshot its target.
		my $device = shift @on;
		$device->{power} = 0;
		$device->{reason} = 'too cool';
		push @actions, $device;
	}
}
elsif ( @on && @off ) {    # between limits, switch if appropiate
	                       # turn off ac that has overshot its target.
	if (0) { }
	elsif ( $on[0]{demand_off} < $off[0]{demand_on} && $off[0]{demand_on} > 1) {
		my $device = $on[0];
		$device->{power} = 0;
		$device->{reason} = 'swap';
		push @actions, $device;
		$device = $off[0];
		$device->{power} = 1;
		$device->{reason} = 'swap';
		push @actions, $device;
	}
	elsif ( $on[0]{demand_off} < $demand_off_threshold ) {
		my $device = $on[0];
		$device->{power} = 0;
		$device->{reason} = 'too cool';
		push @actions, $device;
	}
}

if ( @actions && ! $cron_mode ) {
	warn $status;
	warn __PACKAGE__ . ':' . __LINE__ . $" . Data::Dumper->Dump( [\@off],     ['off'] );
	warn __PACKAGE__ . ':' . __LINE__ . $" . Data::Dumper->Dump( [\@on],      ['on'] );
	warn __PACKAGE__ . ':' . __LINE__ . $" . Data::Dumper->Dump( [\@actions], ['actions'] );
}



for my $action (@actions) {
	push @title, "$action->{name}(" . ( $action->{power} ? 'on' : 'off' ).')';
	push @facts, "$action->{name} ($action->{reason}): " . ( $action->{power} ? 'on' : 'off' );
	warn "$action->{name}: Power => $action->{power}, SetTemperature => " . ( $rooms{ $action->{name} }{target} - $overshoot ) unless $cron_mode;
	$d = $qmel->set_ac( $action->{name},
		{ Power => $action->{power}, SetTemperature => ( $rooms{ $action->{name} }{target} - $overshoot ) } );

	#warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$d], ['d']);
}

my $text = join ', ', @facts;
my $title = join ', ', @title;
say $title;
say $text;

 
# send a notification
$push->message( 
  title => $title, 
  text => $text,
	priority => 0,
) if $cron_mode && @actions;

$pid_file->remove;
unlink '/tmp/run_auto_ac';
sub median {
	sum( ( sort { $a <=> $b } @_ )[int( $#_ / 2 ), ceil( $#_ / 2 )] ) / 2;
}
