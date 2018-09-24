#!/usr/bin/perl
use strict;
use warnings;
use 5.020;
use Data::Dumper;
use Net::MQTT::Simple;
use Date::Parse;
use Getopt::Long;
use JSON;
use File::Slurp qw(slurp);
use enum qw(ERROR WARNING ACTION INFO DEBUG);

# this needs some refactoring

# use this commands to set up the links for munin node
# munin-node-configure --suggest --libdir /usr/local/lib/home_automation/ --shell | sh
# systemctl restart munin-node.service

#%# family=auto
#%# capabilities=autoconf suggest

use lib qw( lib /usr/local/lib/home_automation/perl );
use config;

my $max_age = 360;

my $verbose = ERROR;
my %telemetry;
my $data_file = '/tmp/heat.pl'; # TODO: use $config->{files}{heater_json_file}

if ($ARGV[0] && $ARGV[0] eq 'autoconf') {
	say 'yes' and exit if -e $data_file;
	say 'no';
	exit;
}

my ( $mode, $room );
if ( $0 =~ /heat_([[:alpha:]]+)(?:_(\w+))?$/ ) {
	( $mode, $room ) = ( $1, $2 );
}

my $rooms;
my $creation_time;
eval slurp $data_file;

if ($ARGV[0] && $ARGV[0] eq 'suggest') {
	if (defined $rooms) {
		say 'rooms';
		say 'floors';
		say 'powers';
		for my $key (keys %$rooms ) {
			say "room_$key";
		}
	}
	exit;
}

my $title = '';
my $info = '';
my $unit = chr(176) . 'C';              # the ° sign in latin1...
my $upper;
my $lower;
my $values = '';

my @rooms = sort keys %$rooms;
$values = join ' ', @rooms;


my @values;
my @config;

if ($mode eq 'powers') {
	$title = 'Power Consumption';
	$info = 'Power Consumtion by room and total';
	$unit = 'W';
	$lower = 0;
	$upper = 8000;
	my $total = 0;
	for my $room_key (@rooms) {
		$total += $rooms->{$room_key}{current_power};
		push @values, "$room_key.value $rooms->{$room_key}{current_power}";
		push @config, "$room_key.label $rooms->{$room_key}{name}";
		push @config, "$room_key.draw AREASTACK";
	}
	push @values, "total.value $total";
	push @config, "total.label Total Power";
	push @config, "total.draw LINE1";
	#push @config, "total.graph no";
	push @config, "total.colour 000000";
	# $values = 'total '.$values;
	$values .= ' total';
} elsif ($mode eq 'rooms') {
	$title = 'Room Temperature';
	$info = '';
	#$lower = 10;
	#$upper = 40;
	for my $room_key (@rooms) {
		push @values, "$room_key.value $rooms->{$room_key}{Raumtemperatur}";
		push @config, "$room_key.label $rooms->{$room_key}{name}";
	}
} elsif ($mode eq 'floors') {
	$title = 'Floor Temperature';
	$info = '';
	#$lower = 10;
	#$upper = 40;
	for my $room_key (@rooms) {
		push @values, "$room_key.value $rooms->{$room_key}{Bodentemperatur}";
		push @config, "$room_key.label $rooms->{$room_key}{name}";
	}
} elsif ($mode eq 'room') {
	$title = "Temperature in $rooms->{$room}{name}";
	$info = '';
	#$lower = 0;
	#$upper = 40;
	my @measurements = qw(Raumtemperatur Bodentemperatur floor_target) ;
	for my $measurement ( @measurements ) {
		next unless defined $rooms->{$room}{$measurement};
		push @values, "${room}_$measurement.value $rooms->{$room}{$measurement}";
		push @config, "${room}_$measurement.label $rooms->{$room}{name} $measurement";
	}
	push @values, "${room}_powered.value ".($rooms->{$room}{powered} ? 10 : 0);
	push @config, "${room}_powered.label $rooms->{$room}{name} Powered";
	push @config, "${room}_powered.info 0 when off, 10 when on.";
	push @config, "${room}_powered.draw AREA";
	$values = join ' ', map {"${room}_$_"} @measurements, "powered";
}

if ( $ARGV[0] && $ARGV[0] eq 'config' ) {
	$lower = "--lower-limit $lower" if defined $lower;
	$upper = "--upper-limit $upper" if defined $upper;
	$lower //= '';
	$upper //= '';
	print <<BLA;
graph_title Heating - $title
graph_args --base 1000 --left-axis-format '%2.1lf' $lower $upper
graph_vlabel $unit
graph_category Heating
graph_info $info
graph_order $values

BLA
	say join "\n", @config;
} else {
	say join "\n", @values;
}

