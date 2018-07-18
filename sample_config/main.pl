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

$config{ac} = {

	# at powers abouve this, idle ACs are turned on, one at a time, ordered by demand
	add_surplus => 1200,    # Watts

	# at powers below that, active ACs are turned off, one at a time, based upon their demand_off
	remove_surplus => 600,    # Watts

	# above this, limits to turn on the AC are lowered, also, if the temperature forecast is high enough
	# ACs are turned on even if they don't have any demand (yet)
	high_surplus => 2400,    # Watts

	# turn on ACs prematurely to counter stronger heat buildup in the roof
	# if the maximum temperature forecast is above this. (only if high_surplus criteria is met)
	hot_day_temp => 25,      # Centigrade

	# TODO: reduce the set temperature overshoot by one degree to resist increased heat ingression
	# again, only if high_surplus is met.
	super_hot_day_temp => 30,      # Centigrade

	# MEl-Cloud
	# 0 english
	# 1 russian
	# 4 german
	# 7 french
	language => 4, # unused
	email    => 'your@username',
	password => 'password',
};

# Room config:
# demand_on = (room_temp - target) * weight
# meaning: higher weight makes the AC react more quickly
# demand_off = (floor_temp - target) / weight
# meaning: higher weight keeps the AC on longer.
# the power figure is not yet used and just an estimate.
# also, it is rarely applicable because the AC use far less power
# once they have reached their target temperature.
# maximum is the highes allowable temperature.
# TODO: turn on AC to prevent rooms from overheating regardless of the available power
# serial: monitor your XHR calls to figure them out or read them off the label on the unit.
$config{ac}{rooms} = {
	tvroom => {
		weight  => 0.9,
		target  => 23,
		maximum => 28,
		power   => 1400,
		serial  => 12345,
	},
	bedroomr => {
		weight  => 1,
		target  => 23,
		maximum => 27,
		power   => 700,
		serial  => 23456,
	},
	Laboratory => {
		weight  => 1.7,
		target  => 23,
		maximum => 26,
		power   => 700,
		serial  => 34567,
	},
};



$config{shutter} = {
	temperature_threshold => 24, # do not close below that
	hot_day_temperature   => 26, # beyond that the day is considered hot
	altitude              => 25, # close while sun is higher than that
	hot_day_altitude      => 20, # close early on a hot day
	min_bright_hours      => 2,  # do not close on a cloudy day
	cloudiness_threshold  => 70, # transform hourly 0 - 100% values to yes/no for countimg
	overlap_hours		  => 2,  # not used at the moment
};

# fhem ( https://fhem.de/ ) calls to trigger scens:
# fhem.pl <port> "set tahoma_<scene_id> startAt <msec_from_now>"
# e.g.
# fhem.pl 7072 "set tahoma_123 startAt 3600000"
# means: "start tahoma_123 in one hour"
$config{shutter}{presets} = {
	day_n_down  => '', # 18
	day_n_up    => '', # 06
	day_ne_down => '', # 21
	day_ne_up   => '', # 09
	day_e_down  => '', # 00
	day_e_up    => '', # 12
	day_se_down => 'tahoma_1', # 03
	day_se_up   => 'tahoma_2', # 15
	day_s_down  => '', # 06
	day_s_up    => '', # 18
	day_sw_down => 'tahoma_3', # 09
	day_sw_up   => 'tahoma_4', # 21
	day_w_down  => '', # 12
	day_w_up    => '', # 24
	day_nw_down => 'tahoma_5', # 15
	day_nw_up   => 'tahoma_6', # 03
};

# time offsets to allow for a brighter flat during the time that side is still in the shade.
my $h = 3_600_000; # one hour in tahoma units (ms)
$config{shutter}{offsets} = {
	day_n_down  => 0,          # 18
	day_n_up    => 0,          # 06
	day_ne_down => 0,          # 21
	day_ne_up   => -2 * $h,    # 09
	day_e_down  => 0,          # 00
	day_e_up    => -1.5 * $h,    # 12
	day_se_down => 0,          # 03
	day_se_up   => -1 * $h,    # 15
	day_s_down  => 0.5 * $h,     # 06
	day_s_up    => -0.5 * $h,    # 18
	day_sw_down => 1 * $h,     # 09
	day_sw_up   => 0,          # 21
	day_w_down  => 1.5 * $h,     # 12
	day_w_up    => 0,          # 24
	day_nw_down => 2 * $h,     # 15
	day_nw_up   => 0,          # 03
};

