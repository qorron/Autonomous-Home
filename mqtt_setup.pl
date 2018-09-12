#!/usr/bin/perl
use strict;
use warnings;
use 5.020;
use Data::Dumper;
use Net::MQTT::Simple;
use Getopt::Long;
use JSON;
use enum qw(ERROR WARNING ACTION INFO DEBUG);
use YAML::XS;
use Time::Out qw(timeout) ;

use lib qw( . /usr/local/lib/home_automation/perl );
use config;

my $conf = config->new();
my $mqtt = Net::MQTT::Simple->new($conf->{host}{mqtt});

# script to initialize (set OTA url, model, etc. and reboot),
# configure (name, options, etc..) and update all known sonoff
# modules with the tasmota open source firmware.
# https://github.com/arendst/Sonoff-Tasmota/

# argument handling goes here..
my ($upgrade, $init, $config, $version, $dump_config, $beta);
my $verbose = INFO;
my $critical = ERROR;
$beta = 1;

my @reset_options = qw( FullTopic Module GroupTopic GPIO NtpServer Password Password MqttClient MqttHost MqttPassword MqttPort MqttUser Prefix Topic );
my $select_module;
GetOptions(
	"upgrade"       => \$upgrade,
	"init"          => \$init,
	"config"        => \$config,
	"verbose=i"     => \$verbose,
	"crititical=i"  => \$critical,
	"version=s"     => \$version,
	"dump-config=s" => \$dump_config,
	"beta!"         => \$beta,
	"module=s"      => \$select_module,
);

# common options like OTA url, mqtt host, logging and so on.
my $common          = $conf->{mqtt}{common};
# module type specific options
my $module_defaults = $conf->{mqtt}{module_defaults};
# all the modules
our $modules = $conf->{mqtt}{modules};

my %config = (
	common          => $common,
	module_defaults => $module_defaults,
	modules         => $modules,
);
if ($dump_config) {
	say Dump \%config if $dump_config eq 'yaml';
	say to_json(\%config, {utf8 => 1, pretty => 1}) if $dump_config eq 'json';
	exit;
}


for my $name ( keys %$modules ) {
	for my $option (keys %{$modules->{$name}{config}}) {
		if ($option eq 'FriendlyName') {
			$modules->{$name}{FriendlyName} = $modules->{$name}{config}{FriendlyName};
			last;
		}
	}
}





MODULE: for my $name ( keys %$modules ) {

	next if $select_module && $modules->{$name}{config}{Topic} ne $select_module;
	next if $beta && !$modules->{$name}{beta};

	chat(INFO, "\n  ##### Module: $name '$modules->{$name}{FriendlyName}' #####");

	# update
	# ensure the OTA url is set, then issue the update command.
	# perhaps wait 2-5 seconds in between to ensure nothing gets jammed
	if ( $upgrade && $version ) {
		chat(ACTION, "Upgrade, current version: $version");
		update_module($name);
	}

	# init
	# set options and at last the model 'cause it causes the module to reboot
	if ($init) {
		chat(ACTION, "Initializing...");
		ensure_option($name, 'Module', $modules->{$name}{Module} );
		for my $init_option ( keys %{ $modules->{$name}{init} } ) {
			ensure_option( $name, $init_option, $modules->{$name}{init}{$init_option} );
		}
	}

	# config
	# set all config options, nothing special here
	if ($config) {
		chat(ACTION, "Configuring...");
		set_defaults($name);
		set_module_defaults($name);
		for my $config_option ( keys %{ $modules->{$name}{config} } ) {
			ensure_option( $name, $config_option, $modules->{$name}{config}{$config_option} );
		}
	}
}

# ...


sub update_module {
	my $name = shift;
	my $command_topic = "cmnd/$name/Status"; # cmnd/DVES_80885E/Status -m '2'
	my $result_topic = "stat/$name/STATUS2";
	my $response = send_command($command_topic, 2, $result_topic);
	my $current_version = $response->{StatusFWR}{Program} // $response->{StatusFWR}{Version};
	chat(INFO, "Module Version: $current_version");
	if ($current_version ne $version) {
		chat(INFO, "Setting Defaults");
		set_defaults($name);
		chat(INFO, "Upgrading...");
		$mqtt->publish("cmnd/$name/Upgrade" => 1);
		waitfor_module($name);
	} else {
		chat(INFO, "Module is up to date.");
	}
}

sub waitfor_module {

# 09/20/17 16:19:59 tele/sonoff/INFO1 {"Module":"Sonoff Touch", "Version":"5.2.3", "FallbackTopic":"DVES_80885E", "GroupTopic":"sonoffs"}
# 09/20/17 16:19:59 test/sonoff/tele/INFO1
	our $name            = shift;
	chat(INFO, "Waiting for: $name");
	my $message_handler = sub {
		my ( $topic, $message ) = @_;
		my $respone = parse_response($message);
		if ( exists $respone->{FallbackTopic} ) {
			if ( $respone->{FallbackTopic} eq $name ) {
				chat( ACTION, "Module '$name' came back online as '$respone->{Module}' with Version '$respone->{Version}'." );
				$mqtt->{stop_loop} = 1;
			}
			else {
				chat( INFO, "Another Module '$respone->{FallbackTopic}' came online, we look for '$name' ignoring: '$message'" );
			}
		}
		else {
			chat( INFO, "Message did not contain a FallbackTopic: '$message'" )

		}
		};
	chat(DEBUG, "Subscribing to generic INFO1 Topics");
	$mqtt->subscribe(
		'tele/+/INFO1' => $message_handler,
		'+/+/tele/INFO1' => $message_handler,
	);

	$mqtt->run();
	chat(DEBUG, "Unsubscribing from generic INFO1 Topics");
	$mqtt->unsubscribe('tele/+/INFO1', '+/+/tele/INFO1');
}

sub set_defaults {
	my $name = shift;
	for my $key (keys %$common) {
		ensure_option( $name, $key, $common->{$key} );
	}
}
	
sub set_module_defaults {
	my $name = shift;
	if ( exists $module_defaults->{ $modules->{$name}{Module} } ) {
		for my $default_option ( keys %{ $module_defaults->{ $modules->{$name}{Module} } } ) {
			ensure_option( $name, $default_option, $module_defaults->{ $modules->{$name}{Module} }{$default_option} );
		}
	}
}

sub ensure_option {
	my ( $fallback, $option, $value ) = @_;
	my $generic_name = $option;
	$generic_name =~ s/^([a-z]+).*$/$1/i;    # currently there is no SetOption<n> that triggers a restart
	if ( $generic_name ~~ @reset_options ) {
		chat( DEBUG, "ensuring $option is $value" );
		my $respone = query_option( $fallback, $option );

		#my $respone = parse_response( $respone_json);
		if ( exists $respone->{$option} ) {
			my $option_string = $respone->{$option};
			my ( $option_value, $option_name ) = ( $option_string, $option_string );
			if ( $option_string =~ /^(\d+) (.+)$/ ) {
				( $option_value, $option_name ) = ( $1, $2 );
				chat( DEBUG, "found number $option_value with description $option_name" );
			}
			else {
				# no Module in respone
				#chat( ERROR, "Unable to read Module string: '$module_string'" );
			}
			if ( $option_value eq $value ) {    # $modules->{$fallback}{Module} ) {

				# all ok, option is already set
				chat( INFO, "Option $option is already set to '$option_name'." );
			}
			else {
				# set module number
				chat( ACTION, "Option $option is $option_name resetting to $value, Module will reboot!" );
				set_option( $fallback, $option, $value );
				waitfor_module($fallback);
			}
		}
		else {
			# no Module in respone
			chat( ERROR, "No $option in respone: '" . Dumper($respone) . "'" );
		}
	}
	else {
		my $val_text = (ref $value eq 'ARRAY' ? 'Multivalue: '.join ', ', map {"'$_'"} @$value: $value);
		chat( ACTION, "Setting option $option to $val_text. " );
		set_option( $fallback, $option, $value );
	}
}

sub query_option {
	my ( $fallback, $option ) = @_;
	return set_option( $fallback, $option, '' );
}

sub set_option {
	my ( $fallback, $option, $values ) = @_;

	my $result;
	my $command_topic = "cmnd/$fallback/$option";
	my $result_topic = "stat/$fallback/RESULT";
	$values = [$values] unless 'ARRAY' eq ref $values;
	my %return;
	for my $value (@$values) {
		my $return = send_command($command_topic, $value, $result_topic);
		%return = (%return, %$return);
	}
	return \%return;
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
	timeout 10 => sub {

		# your code goes were and will be interrupted if it runs
		# for more than $nb_secs seconds.
		$mqtt->run;
	};
	if ($@) {

		# operation timed-out
		warn "command response timed out";
		$mqtt->unsubscribe($result_topic);
		next MODULE;
	}
	chat( DEBUG, "Unsubscribing from: '$result_topic'" );
	$mqtt->unsubscribe($result_topic);
	return parse_response( $result, WARNING );
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
