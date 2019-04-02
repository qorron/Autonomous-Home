#!/usr/bin/perl
use strict;
use warnings;
use 5.020;
use Data::Dumper;

# this subscribes to the STATE telemetry topics on the mqtt and resets devices that have a low RSSI over a period of time

use JSON;
use Net::MQTT::Simple;
use Date::Parse;

use lib qw( lib /usr/local/lib/home_automation/perl );
use config;

 
our $conf = config->new();
my $mqtt = Net::MQTT::Simple->new($conf->{host}{mqtt});

our %low_rssi_hits;

$mqtt->run(
    "tasmota/+/tele/STATE" => sub {
		my ($full_topic, $message, $retain) = @_;
		parse_state($full_topic, $message, $retain, \&restart_on_low_rssi);
    },
);


sub restart_on_low_rssi {
	my ($topic, $response, $age) = @_;
	if ($age < ($conf->{mqtt}{common}{TelePeriod} + 15)) { # add 15 sec grace period
		if ($response->{Wifi}{RSSI} < $conf->{mqtt}{params}{min_rssi}) {
			$low_rssi_hits{$topic}++;
			say "$topic has $response->{Wifi}{RSSI} < $conf->{mqtt}{params}{min_rssi} $low_rssi_hits{$topic} times ($age)";
			if ($low_rssi_hits{$topic} > $conf->{mqtt}{params}{min_rssi_hit_limit}) {
				say "$low_rssi_hits{$topic} > $conf->{mqtt}{params}{min_rssi_hit_limit} times, resetting";
				delete $low_rssi_hits{$topic};
				$mqtt->publish("tasmota/$topic/cmnd/Restart" => 1);
			}
		} else {
			delete $low_rssi_hits{$topic};
		}
	}
}

sub parse_state { # TODO move this to our own MQTT::Tasmota module
	my ($full_topic, $message, $retain, $callback) = @_;
	my $topic = '';
	if ($full_topic =~ m{^tasmota/(\w+)/tele/STATE$} ) {
		$topic = $1;
		my $response;
		eval { $response = decode_json $message};
		if ($response) {
			my $age = time - str2time( $response->{Time} );
			$callback->($topic, $response, $age);
		}
		else {
			# not parsable json
		}
	}
}
