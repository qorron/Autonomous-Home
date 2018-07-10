#!/usr/bin/perl
use strict;
use warnings;
use 5.020;
use Data::Dumper;

%config = (
	latitude           => 51.1789,
	longitude          => -1.8262,
	weather_cache_file => '/tmp/weather.storable',
);

$config{host} = {
	grid   => '10.0.0.2',    # device measuring el. power flow to and from the grid
	solar  => '10.0.0.3',    # inverter, tells the power currently produces by the panels
	symcon => '10.0.0.4',    # local symcon device controlling the heater
};

$config{files} = {
	power_balance_file   => '/tmp/power_balance.db',
	weather_cache_file   => '/tmp/weather.storable',
	heater_json_file     => "/tmp/heat.json",
	solar_json_file      => "/tmp/solar.json",
	power_flow_json_file => "/tmp/power_flow.json",
};

$config{heater} = {
	symcon_auth => 'Basic base64ed_password',    # get that by observing the web UI
	symcon_root => 123,                          # root id, use web UI & inspect
};

# when rooms are differently named in the symcon unite
$config{heater}{translation} = {
	'Laboratory' => 'Lab',
	'Library'    => "B\x{fc}ro",
};

# power rating for the heater units in every room
$config{heater}{power} = {
	'Library'    => 732,
	'Laboratory' => 1423,
};

