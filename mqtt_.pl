#!/usr/bin/perl
use strict;
use warnings;
use 5.020;
use Data::Dumper;
use Date::Parse;
use Getopt::Long;
use JSON;
use File::Slurp qw(slurp);
use File::Basename;
use enum qw(ERROR WARNING ACTION INFO DEBUG);

use lib qw( lib /usr/local/lib/home_automation/perl );
use Net::MQTT::Simple;
use config;

my @sensors = qw( AM2301 DS18B20 );
my @sensor_measurements = qw(Temperature Humidity);

my $conf = config->new();
my $mqtt = Net::MQTT::Simple->new($conf->{host}{mqtt});

my $max_age = 360;

my $verbose = ERROR;
my %telemetry;

my ( $mode, $topic );
if ( $0 =~ /mqtt_([[:alpha:]]+)(?:_(\w+))?$/ ) {
	( $mode, $topic ) = ( $1, $2 );
}

my $aps;

my $dirname = dirname(__FILE__);
my $config_file = '/usr/local/lib/home_automation/AP_names.pl';
if ( -e "$dirname/AP_names.pl") {
	$config_file = "$dirname/AP_names.pl";
}

eval slurp $config_file;

if ( $mode eq 'sensor' ) {
	$mqtt->run(
		"tasmota/$topic/tele/SENSOR" => sub {
			my ( $full_topic, $message ) = @_;
			read_sensor_data($message);
			$mqtt->{stop_loop} = 1;
		},
	);
	$mqtt->unsubscribe("tasmota/$topic/tele/SENSOR");

	my $abs_hum_postfix = '';
	if ( exists $telemetry{$topic}{Temperature_AM2301} && exists $telemetry{$topic}{Humidity_AM2301} ) {
		$abs_hum_postfix = '_AM2301';
	}
	

	my @all_values = qw(Temperature Humidity Light Noise AirQuality);
	for my $sensor (@sensors) {
		for my $sensor_measurement (@sensor_measurements) {
			push @all_values, "${sensor_measurement}_$sensor";
		}
	}

	my @values = grep { exists $telemetry{$topic}->{$_} } @all_values;

	if ( $ARGV[0] && $ARGV[0] eq 'config' ) {
		my $deg = chr(176) . 'C';              # the ° sign in latin1...
		my $values = join ' ', @values;
		my $name = get_friendly_name($topic);
		print <<BLA;
graph_title Sensor Data of $name
graph_args --base 1000 --lower-limit 0 --upper-limit 100
graph_vlabel $deg/%
graph_category Enviroment
graph_info This graph monitors the Sensor Data of $name
graph_order $values

BLA

		foreach (@values) {
			say "$_.label $_";
			say "$_.info Sensor Data: $_";
		}
		if ( exists $telemetry{$topic}{"Temperature$abs_hum_postfix"} && exists $telemetry{$topic}{"Humidity$abs_hum_postfix"} ) {
			say "abs_hum$abs_hum_postfix.label Absolute Humidity$abs_hum_postfix";
			say "abs_hum$abs_hum_postfix.info Absolute humidity in g/m^3";
		}
	}
	else {
		if ( exists $telemetry{$topic}{Time} ) {
			foreach (@values) {
				$telemetry{$topic}{$_} = 'nan' if $telemetry{$topic}{age} > $max_age;
				say "$_.value $telemetry{$topic}{$_}";
			}
			my $postfix = '';
			if ( exists $telemetry{$topic}{"Temperature$abs_hum_postfix"} && exists $telemetry{$topic}{"Humidity$abs_hum_postfix"} )
			{
				# do the math for absolute humidity
# So, saturation vapour pressure in the pure phase is
# e_w(t)=6.112 \cdot e^{\frac{17.62t}{243.12+t}}
# 
# Saturation vapour pressure of moist air is
# {e_w}^{'}(p,t)=f(p) \cdot e_w(t)
# 
# where pressure function f(p) is
# f(p)=1.0016+3.15\cdot10^{-6}p-0.074\cdot p^{-1}
# 
# Units of temperature are degrees centigrade and units of pressure are hectopascals (hPa). 1 hectopascal = 100 pascals.
# From relative humidity and saturation vapour pressure we can find actual vapour pressure.
# e= e_w \frac{RH}{100}
# 
# Then we can use the general law of perfect gases
# PV=\frac{m}{M}RT
# 
# In our case this is
# eV=mR_vT
# 
# where R is universal gas constant equals to 8313.6, and Rv - specific gas constant for water vapour equals to 461.5
# 
# Thus we can express mass to volume ratio as
# \frac{m}{V}=\frac{e}{R_vT}
# which is absolute humidity.
# 

				my $t = $telemetry{$topic}{"Temperature$abs_hum_postfix"};
				my $h = $telemetry{$topic}{"Humidity$abs_hum_postfix"};
				my $p    = slurp '/tmp/pressure';
				my $e_w  = 6.112 * exp( ( 17.62 * $t ) / ( 243.12 + $t ) );
				my $f    = 1.0016 + (3.15 * (10 ** -6) * $p) - (0.074 * ($p ** -1));
				my $e_w_ = $f * $e_w;
				my $e = $e_w_ * $h / 100;
				my $abs_hum = 1000*100*$e/(461.5*(273.15 + $t));
				#say "p $p\nt $t\ne_w $e_w\nf $f\ne_w_ $e_w_\ne $e";
				say "abs_hum$abs_hum_postfix.value $abs_hum";
			}
		}
	}

} elsif ( $mode eq 'rssi' || $mode eq 'vcc') {

    eval {
        local $SIG{ALRM} = sub { die "alarm\n" };    # NB: \n required
        alarm 1;

		$mqtt->run(
			"tasmota/+/tele/STATE" => sub {
				my ( $full_topic, $message ) = @_;

				# warn "$full_topic, $message";
				read_telemetry_data($full_topic, $message);
			},

	#     "#" => sub {
	#         my ($return_topic, $message) = @_;
	#         print "[$return_topic] $message\n";
	#     },
		);

        alarm 0;
    };
    if ($@) {

        # timed out
        my $err = $@;
        die $err unless $err eq "alarm\n";    # propagate unexpected errors
        # say "server timeout";
    }
    else {

        # didn't
    }
	$mqtt->unsubscribe('tasmota/+/tele/STATE');
	my @devices = sort keys %telemetry;
	if ( $ARGV[0] && $ARGV[0] eq 'config' ) {
		my $values = join ' ', @devices;
		my $args = {
			rssi => '--base 1000 --lower-limit 0 --upper-limit 100',
			vcc  => '--base 1000' ,
		}->{$mode};
		my $vlabel = { rssi => '%', vcc => 'V', }->{$mode};

		print <<BLA;
graph_title Sensor Data of $mode
graph_args $args
graph_vlabel $vlabel
graph_category Home Autmation
graph_info This graph monitors the Sensor Data of $mode
graph_order $values

BLA

		foreach (@devices) {
			$telemetry{$_}{friendly_name} = get_friendly_name($_);
			say "$_.label $telemetry{$_}{friendly_name}" if $telemetry{$_}{friendly_name};
			say "$_.info " . get_rssi_info_string($_);
		}

	}
	else {

		foreach (@devices) {
			my $value = (
				$telemetry{$_}{age} <= $max_age
				? { rssi => $telemetry{$_}{Wifi}{RSSI}, vcc => $telemetry{$_}{Vcc} }->{$mode}
				: 'nan'
			);
			say "$_.value $value";
		}
	}
}

sub get_rssi_info_string {
	# "SSId":"wald", "RSSI":78, "APMac":"06:18:D6:2B:2C:F8"
	my $topic = shift;
	my $name = $telemetry{$topic}{friendly_name}? $telemetry{$topic}{friendly_name} : $topic;
	my $ap = exists $aps->{lc $telemetry{$topic}{Wifi}{APMac}} ? $aps->{lc $telemetry{$topic}{Wifi}{APMac}}: lc $telemetry{$topic}{Wifi}{APMac};
	return "$name on '$telemetry{$topic}{Wifi}{SSId}' ($ap)";
}



sub get_friendly_name {
	my $topic = shift;
	my $option = 'FriendlyName';
	return $topic if exists $telemetry{$topic}{age} && $telemetry{$topic}{age} > $max_age;
	my $response =  get_option($topic, $option);
    #my $response = parse_response( $respone_json);
    if ( exists $response->{$option.'1'} ) {
		return $response->{$option.'1'};
	}
	return $topic;
}


sub read_telemetry_data {
	my ($full_topic, $message) = @_;
	my $topic = '';
	if ($full_topic =~ m{^tasmota/(\w+)/tele/STATE$} ) {
		$topic = $1;
		my $response;
		eval { $response = decode_json $message};
		if ($response) {
			my $age = time - str2time( $response->{Time} );
			# perl -MData::Dumper -E '%e = (a => 1, b => 2); $e = {b=>3, c =>4}; @e{keys %$e} = values %$e; say Dumper \%e; say join " ", keys %e; say join " ", values %e;'
			# appearantly perl randomizes the order, but keeps keys and values in sync. TODO: check that with other perl mongers
			@{$telemetry{$topic}}{keys %$response} = values %$response;
			$telemetry{$topic}{age} = $age;
		}
		else {
			# 		# not parsable json
			# 		$json //= '(null)';
			# 		chat( $on_error, "Unable to parse json: '$json'" );
		}
		
	}

}



sub read_sensor_data {
	my $json = shift;

	my $response;

	eval { $response = decode_json $json};
	if ($response) {
		my $time = $response->{Time};

		# hack to deal with modules with 2 sensors
		if ( exists $response->{AM2301} && exists $response->{DS18B20} ) {
			for my $sensor (qw( AM2301 DS18B20 )) {
				for my $key ( keys %{ $response->{$sensor} } ) {
					$response->{ $key . '_' . $sensor } = $response->{$sensor}{$key};
				}
				delete $response->{$sensor};
			}
		}
		elsif ( exists $response->{AM2301} ) {    # temp + hum
			$response = $response->{AM2301};
		}
		elsif ( exists $response->{DS18B20} ) {    # temp
			$response = $response->{DS18B20};
		}
		elsif ( exists $response->{Noise} ) {      # sonoff SC, full sensor array
		}
		else {
			return;                                # no sensor data
		}
		$response->{Time} = $time;                 # restore Time
		$telemetry{$topic} = $response;
		my $age = time - str2time( $response->{Time} );
		# perl -MData::Dumper -E '%e = (a => 1, b => 2); $e = {b=>3, c =>4}; @e{keys %$e} = values %$e; say Dumper \%e; say join " ", keys %e; say join " ", values %e;'
		# appearantly perl randomizes the order, but keeps keys and values in sync. TODO: check that with other perl mongers
		@{$telemetry{$topic}}{keys %$response} = values %$response;
		$telemetry{$topic}{age} = $age;
	}
	else {
		# 		# not parsable json
		# 		$json //= '(null)';
		# 		chat( $on_error, "Unable to parse json: '$json'" );
	}
}

exit;

# argument handling goes here..
my ($upgrade, $init, $config, $version);
my $critical = ERROR;

GetOptions(
	"upgrade" => \$upgrade,
	"init"    => \$init,
	"config"  => \$config,
	"verbose=i" => \$verbose,
	"crititical=i" => \$critical,
	"version=s" => \$version,
);
# yadda yadda yadda...

# common options like OTA url, mqtt host logging and so on.
my $common = {
	FullTopic => "tasmota/%topic%/%prefix%/",
	OtaUrl  => 'http://192.168.2.2:80/api/arduino/sonoff.ino.bin',
	LogHost => '192.168.2.2',
	LogPort => '514',
	SysLog  => '2',                                                  # 0 off, 1 error, 2 info, 3 debug, 4 all
};


# TODO move the module specific stuff in a seperate file

# list of fallback names
# we need this exactly why?
my @names = qw();

# hash of fallback names with a list of init commands
# perhaps add a subhash for options
# Modules:
#  1 (Sonoff Basic)     21 (Sonoff SC)
#  2 (Sonoff RF)        22 (Sonoff BN-SZ)
#  3 (Sonoff SV)        23 (Sonoff 4CH Pro)
#  4 (Sonoff TH)        24 (Huafan SS)
#  5 (Sonoff Dual)      25 (Sonoff Bridge)
#  6 (Sonoff Pow)       26 (Sonoff B1)
#  7 (Sonoff 4CH)       27 (AiLight)
#  8 (S20 Socket)       28 (Sonoff T1 1CH)
#  9 (Slampher)         29 (Sonoff T1 2CH)
# 10 (Sonoff Touch)     30 (Sonoff T1 3CH)
# 11 (Sonoff LED)       31 (Supla Espablo)
# 12 (1 Channel)
# 13 (4 Channel)
# 14 (Motor C/AC)
# 15 (ElectroDragon)
# 16 (EXS Relay)
# 17 (WiOn)
# 18 (WeMos D1 mini)
# 19 (Sonoff Dev)
# 20 (H801)

sub get_option {
	my ( $topic, $option ) = @_;
	my $command_topic = "tasmota/$topic/cmnd/$option";
	my $result_topic = "tasmota/$topic/stat/RESULT";
	return send_command($command_topic, '', $result_topic);
}


sub send_command {
	my ($command_topic, $message, $result_topic) = @_;
	chat(DEBUG, "Subscribing to: '$result_topic'");
	our $result = '';
	$mqtt->subscribe(
		$result_topic => sub {
			chat(DEBUG, join( '=>', @_));
			$result = $_[1];
			$mqtt->{stop_loop} = 1;
		},
	);

	chat(DEBUG, "Publishing: '$command_topic' => '$message'");
	$mqtt->publish( $command_topic => $message );
    eval {
        local $SIG{ALRM} = sub { die "alarm\n" };    # NB: \n required
        alarm 1;

		$mqtt->run();
		alarm 0;
    };
    if ($@) {

        # timed out
        my $err = $@;
        die $err unless $err eq "alarm\n";    # propagate unexpected errors
    }
    else {

        # didn't
    }
	chat(DEBUG, "Unsubscribing from: '$result_topic'");
	$mqtt->unsubscribe($result_topic);
	return parse_response( $result, WARNING);
}

sub parse_response {
	my ( $json, $on_error ) = @_;
	$on_error //= ERROR;
	my $response;

	# workaround for https://github.com/arendst/Sonoff-Tasmota/issues/897
	# {"GPIO1":0 (None), "GPIO3":0 (None), "GPIO4":0 (None), "GPIO14":0 (None)}
	if ($json =~ /"GPIO\d\d?":\d/) {
		$json =~ s/"GPIO(\d\d?)":(\d\d? [^,\}]+)/"GPIO$1":"$2"/g;
	}
	eval { $response = decode_json $json};
	if ($response) {
		return $response;
	}
	else {
		# not parsable json
		$json //= '(null)';
		chat( $on_error, "Unable to parse json: '$json'" );
	}
}

sub chat {
	my ($level, $message) = @_;
	if ($level <= $verbose) {
		if ($level <= $critical) {
			die $message;
		} else {
			say $message;
		}
	}	
}
