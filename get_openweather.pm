#!/usr/bin/perl

package get_openweather;

use strict;
use warnings;
use 5.020;
use Data::Dumper;
use Weather::OpenWeatherMap; # use this for current weather

# caching and everything else is hadnled by Weather::OpenWeatherMap
# so this is just a wrapper so I don't have to parameterize the api key and the location every time I use it.

use lib qw( . /usr/local/lib/home_automation/perl );
use config;

sub kelvin {
	return -273.15;
}

sub get_open_weather_map {
	my $self = {};
	$self->{config} = config->new();

	# https://api.openweathermap.org/data/2.5/weather?lat=47.056427&lon=16.074869&appid=6b06ed93a0df451c29890120674217cf
	# https://metacpan.org/pod/Weather::OpenWeatherMap
	my $wx = Weather::OpenWeatherMap->new(
		api_key      => $self->{config}{keys}{open_weather},
		cache        => 1,
		cache_expiry => 120,
	);
	return $wx->get_weather(

		# 'location =>' is mandatory.
		#  These are all valid location strings:
		#  By name:
		#   'Manchester, NH'
		#   'London, UK'
		#  By OpenWeatherMap city code:
		#   5089178
		#  By latitude/longitude:
		#   'lat 42, long -71'
		location => "lat $self->{config}{latitude}, long $self->{config}{longitude}",

		# Set 'forecast => 1' to get the forecast,
		# omit or set to false for current weather:
		# forecast => 1,

		# If 'forecast' is true, you can ask for an hourly (rather than daily)
		# forecast report:
		# hourly => 1,

		# If 'forecast' is true, you can specify the number of days to fetch
		# (up to 16 for daily reports, 5 for hourly reports):
		# days => 3,

		# Optional tag for identifying the response to this request:
		# tag  => 'foo',
	);
}

42;

