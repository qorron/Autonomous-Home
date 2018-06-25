#!/usr/bin/perl
=pod
this is just a demo on how to use the weather cache.
it refreshes the cache so it can be used to prep it before something else runs and needs a valid cache
=cut

use strict;
use warnings;
use 5.020;
use Data::Dumper;

use lib qw( . /usr/local/lib/home_automation/perl );
use get_weather;

my $weather = get_weather->new( max_age => 1800 ); # seconds

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

