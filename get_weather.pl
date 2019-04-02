#!/usr/bin/perl
=pod
this is just a demo on how to use the weather cache.
it refreshes the cache so it can be used to prep it before something else runs and needs a valid cache
=cut

use strict;
use warnings;
use 5.020;
use Data::Dumper;

use lib qw( lib . /usr/local/lib/home_automation/perl );
use get_weather;
use get_openweather;

my $weather = get_weather->new( max_age => 1800 ); # seconds

my $ow = get_openweather::get_open_weather_map();

say join ', ', $ow->station, $ow->name, $ow->country;
say 'temp: '.$ow->temp_c;
say 'cond: '.$ow->conditions_terse;
say ''.$ow->conditions_verbose;
say 'hum: '.$ow->humidity;
say 'pressure: '.$ow->pressure;
say 'wind: '.$ow->wind_speed_kph;
say 'gust: '.$ow->wind_gust_kph;
say 'cloud%: '.$ow->cloud_coverage;
say $ow->dt;

my $day = $weather->{cache}{yr_today};
say ref $day;
for my $day ( $weather->{cache}{yr_today}, $weather->{cache}{yr_tomorrow} ) {
	foreach my $dp ( @{ $day->datapoints } ) {
		my $start = $dp->from->hms;
		say ' ' x 4 . 'Temperature: ' . $dp->temperature->celsius . " $start ";
	}
	say '---';
}
say "max temp today (remaining day): $weather->{cache}{max_temp_today}";
say "max temp tomorrow: $weather->{cache}{max_temp_tomorrow}";
say "min temp today (remaining day): $weather->{cache}{min_temp_today}";
say "min temp tomorrow: $weather->{cache}{min_temp_tomorrow}";
