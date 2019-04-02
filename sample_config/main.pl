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

	# do not engage ACs below this temperature
	min_day_temp => 20,

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
	super_hot_day_temperature   => 29, # increased overshoot beyond this
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




$config{mqtt}{params} = {
	min_rssi           => 65,
	min_rssi_hit_limit => 5,
};

$config{mqtt}{common} = {
# to safely quote your passwords please refer to:
# https://perldoc.perl.org/5.26.0/perlop.html#Quote-Like-Operators
# 	SSId1       => 'ssid1',
# 	Password1   => 'pass1',
# 	SSId2       => 'ssid2',
# 	Password2   => 'pass2',
	FullTopic   => "tasmota/%topic%/%prefix%/", # please leave that unchanged since the script depends on that!
	OtaUrl      => 'http://192.168.2.2:80/api/arduino/sonoff.ino.bin',
	LogHost     => '192.168.2.2',
	LogPort     => '514',
	SysLog      => '2',                                                                   # 0 off, 1 error, 2 info, 3 debug, 4 all
	Timezone    => '99',
	PowerRetain => '1',
	seriallog   => '0',    # gets in the way of submodule communication
	SetOption26 => 0,      # 0 (default) Keep using POWER without postfix for single power devices
	                       # 1 Add postfix to all POWER messages
	Latitude    => $config{latitude},
	Longitude   => $config{longitude},
	TelePeriod  => 300, # 300 is the default, the value here is also used to determine staleness.
};
# Modules: (at the time of writing)
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

# module type specific config:
$config{mqtt}{module_defaults} = {
	10 => {    # Sonoff Touch
		'SetOption13' => 1    # single press only
	},
	4 => {                    # Sonoff TH
		'SensorRetain' => 1
	},
	21 => {                   # Sonoff SC
		'SensorRetain' => 1
	},
};

# all your modules
$config{mqtt}{modules} = {
	DVES_123456 => {    # the unique fallback topic
		Module => 10,                              # Sonoff Touch
		init   => { 'GroupTopic' => 'group1', },
		config => {
			'FriendlyName' => 'Wall1',
			'Topic'        => 'wall1',
			'ButtonTopic'  => 'group1',
		},

		# this is a precaution to deploy new stuff on devices you have good acces to
		# they usually reside on you workbench with the serial pin header still attached to them
		beta => 1,                                 # only beta devices are touched by default
	},
	DVES_234567 => {
		Module => 10, # Sonoff Touch
		init   => {
			'GroupTopic' => 'group2', 
		},
		config => {
			'FriendlyName' => 'Wall2', 
			'Topic' => 'wall2', 
			'ButtonTopic' => 'group2', 
		},
		beta => 0,
	},
	DVES_345678 => { # sonoff TH16 1
		Module => 4,
		init   => {
			'GPIO14' => '4',  # temp #### gpio has broken json in 5.7.1
			'GroupTopic' => 'group1', 
		},
		config => {
			'FriendlyName' => 'TH16_1', 
			'Topic' => 'TH16_1', 
			'ButtonTopic' => 'group1', 
		},
		beta => 1,
	},
};
