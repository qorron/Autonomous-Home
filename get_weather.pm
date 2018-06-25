#!/usr/bin/perl
package get_weather;

=pod
this is used to fetch weather forecast data from yr.no and cache the data to make a local copy available for all the small scripts to use without putting load on yr.no
see get_weather.pl on how to use it.
=cut

use strict;
use warnings;
use feature ':5.20';
use Data::Dumper;

use Storable;
use List::Util qw(max);
use Weather::YR;

use lib qw( . /usr/local/lib/home_automation/perl );
use config;

sub new {
	my $that      = shift;
	my %args = @_;
	my $class     = ref $that || $that;

	# my %args = @_;
	my $self = { max_age => $args{max_age}, };
	bless $self, $class;
	$self->init();
	return $self;
}

sub init {
	my $self = shift;
	$self->{config} = config->new();

	$self->load_cache();
	if ( $self->{cache}{yr_time} > ( time - $self->{max_age} ) ) {
		say "cache hit";
	}
	else {
		say "cache miss";
		$self->update_cache();
	}
}

sub load_cache {
	my $self  = shift;
	my $cache = {};
	if ( -e $self->{config}{weather_cache_file} ) {
		$cache = retrieve( $self->{config}{weather_cache_file} );
	}
	$cache->{yr_time} //= 0;
	$self->{cache} = $cache;
}

sub update_cache {
	my $self  = shift;
	my $cache = {};
	my $yr    = Weather::YR->new(
		lat => $self->{config}{latitude},
		lon => $self->{config}{longitude},

		#    tz  => DateTime::TimeZone->new( name => 'Europe/Vienna' ),
		#    tz  => DateTime::TimeZone->new( name => 'UTC' ),
	);
	$cache->{yr_time}     = time;
	$cache->{yr_today}    = $yr->location_forecast->days->[0];    # 1: tomorrow, 0: today (for late night coding)
	$cache->{yr_tomorrow} = $yr->location_forecast->days->[1];    # 1: tomorrow, 0: today (for late night coding)
	$cache->{max_temp_today} =
		max map { $cache->{yr_today}->datapoints->[$_]->temperature->celsius } ( 0 .. $#{ $cache->{yr_today}->datapoints } );
	$cache->{max_temp_tomorrow} = max map { $cache->{yr_tomorrow}->datapoints->[$_]->temperature->celsius }
		( 0 .. $#{ $cache->{yr_tomorrow}->datapoints } );

	store $cache, $self->{config}{weather_cache_file};
	$self->{cache}        = $cache;
}

42;

