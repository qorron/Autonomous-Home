#!/usr/bin/env perl
use 5.024;
use strict;
use warnings;
use DDP;

use File::Basename;
use Path::Tiny;
use JSON;
use Date::Parse;
         
use lib qw( lib /usr/local/lib/home_automation/perl );

my $config = $ARGV[0] && $ARGV[0] eq 'config';

my $all_sensor_data = {};

my $now = time;
for my $file (
    path('/var/local/home_automation/')->children(qr'^zigbee_temper_hum_') )
{
	my $file_age = time - $file->stat->mtime;
	next if $file_age > 24*3600;
    my $module_name;
    $module_name = $1 if $file =~ /zigbee_temper_hum_(\w+)\.json/;
    my $sensor_data = decode_json( $file->slurp_raw );
    my $last_seen   = str2time( $sensor_data->{last_seen} );
    my $age         = $now - $last_seen;
    $sensor_data->{age} = $age/60;
    my $friendly_name = $module_name;
    $friendly_name =~ s/_/ /g;
    $sensor_data->{name_lc}          = lc $module_name;
    $sensor_data->{name_friendly}    = $friendly_name;
    $all_sensor_data->{$module_name} = $sensor_data;
}

print temper_hum($all_sensor_data, $config);
print temper_hum($all_sensor_data, $config, 'all');
print last_seen($all_sensor_data, $config);
print signal($all_sensor_data, $config);
print temper_hum_module( $all_sensor_data->{$_}, $config )
  for sort keys $all_sensor_data->%*;

sub temper_hum {
    my ( $all_data, $config, $all ) = @_;

	$all = '.all' if $all;

    my $return = "multigraph zigbee_temper_hum$all\n";
    $return .= <<CONFIG if ($config);
graph_title Temperature and humidity for Zigbee sensors
graph_args --base 1000 --lower-limit 0 --upper-limit 100
graph_vlabel °C/%
graph_category environment
graph_info This graph shows the temperature and humidity reported by all sensors.

CONFIG

    for my $module_key ( sort keys $all_data->%* ) {
        if ($config) {
            $return .= <<CONFIG;
$all_data->{$module_key}{name_lc}_temperature.label $all_data->{$module_key}{name_friendly} temperature
$all_data->{$module_key}{name_lc}_temperature.type GAUGE
$all_data->{$module_key}{name_lc}_temperature.min 0
$all_data->{$module_key}{name_lc}_temperature.draw LINE1
$all_data->{$module_key}{name_lc}_humidity.label $all_data->{$module_key}{name_friendly} humidity
$all_data->{$module_key}{name_lc}_humidity.type GAUGE
$all_data->{$module_key}{name_lc}_humidity.min 0
$all_data->{$module_key}{name_lc}_humidity.max 100
$all_data->{$module_key}{name_lc}_humidity.draw LINE1

CONFIG
        }
        else {
            $return .= <<VALUE;
$all_data->{$module_key}{name_lc}_temperature.value $all_data->{$module_key}{temperature}
$all_data->{$module_key}{name_lc}_humidity.value $all_data->{$module_key}{humidity}
VALUE

        }
    }
	$return .="\n" unless $config;
    return $return;
}

sub temper_hum_module {
    my ( $module_data, $config ) = @_;

    my $return = "multigraph zigbee_temper_hum.$module_data->{name_lc}\n";
    if ($config) {
        $return .= <<CONFIG;
graph_title Temperature and humidity for $module_data->{name_friendly}
graph_args --base 1000 --lower-limit 0 --upper-limit 100
graph_vlabel °C/%
graph_category environment
graph_info This graph shows the temperature and humidity reported by the sensor: $module_data->{name_lc}

temperature.label Temperature
temperature.type GAUGE
temperature.min 0
temperature.draw LINE1
humidity.label Humidity
humidity.type GAUGE
humidity.min 0
humidity.max 100
humidity.draw LINE1

CONFIG
    }
    else {
        $return .= <<VALUES;
temperature.value $module_data->{temperature}
humidity.value $module_data->{humidity}

VALUES
    }

    return $return;
}
sub last_seen{
    my ( $all_data, $config ) = @_;

    my $return = "multigraph zigbee_last_seen\n";
    $return .= <<CONFIG if ($config);
graph_title Last seen for Zigbee sensors
graph_args --base 1000
graph_vlabel min
graph_category environment
graph_info This graph shows the age of the reported data for all sensors.

CONFIG

    for my $module_key ( sort keys $all_data->%* ) {
        if ($config) {
            $return .= <<CONFIG;
$all_data->{$module_key}{name_lc}_age.label $all_data->{$module_key}{name_friendly} age
$all_data->{$module_key}{name_lc}_age.type GAUGE
$all_data->{$module_key}{name_lc}_age.min 0
$all_data->{$module_key}{name_lc}_age.draw LINE1

CONFIG
        }
        else {
            $return .= <<VALUE;
$all_data->{$module_key}{name_lc}_age.value $all_data->{$module_key}{age}
VALUE

        }
    }
	$return .="\n" unless $config;
    return $return;
}
sub signal{
    my ( $all_data, $config ) = @_;

    my $return = "multigraph zigbee_linkquality\n";
    $return .= <<CONFIG if ($config);
graph_title Signal strength for Zigbee sensors
graph_args --base 1000 --lower-limit 0 --upper-limit 100
graph_vlabel min
graph_category environment
graph_info This graph shows the link quality for all sensors.

CONFIG

    for my $module_key ( sort keys $all_data->%* ) {
        if ($config) {
            $return .= <<CONFIG;
$all_data->{$module_key}{name_lc}_linkquality.label $all_data->{$module_key}{name_friendly} link quality
$all_data->{$module_key}{name_lc}_linkquality.type GAUGE
$all_data->{$module_key}{name_lc}_linkquality.min 0
$all_data->{$module_key}{name_lc}_linkquality.draw LINE1

CONFIG
        }
        else {
            $return .= <<VALUE;
$all_data->{$module_key}{name_lc}_linkquality.value $all_data->{$module_key}{linkquality}
VALUE

        }
    }
	$return .="\n" unless $config;
    return $return;
}
