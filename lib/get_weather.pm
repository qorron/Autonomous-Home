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
use List::Util qw(max min sum);
use Weather::YR; # use this for forecast

use lib qw( . /usr/local/lib/home_automation/perl );
use config;

our $kelvin = -273.15;

sub new {
	my $that      = shift;
	my %args = @_;
	my $class     = ref $that || $that;

	# my %args = @_;
	my $self = { max_age => $args{max_age}, verbose => $args{erbose} };
	bless $self, $class;
	$self->init();
	return $self;
}

sub init {
	my $self = shift;
	$self->{config} = config->new();
	$self->refresh();
}

sub refresh {
	my $self = shift;
	$self->load_cache();
	if ( $self->{cache}{yr_time} > ( time - $self->{max_age} ) ) {
		say "cache hit" if $self->{verbose};
	}
	else {
		say "cache miss" if $self->{verbose};
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
	$cache->{min_temp_today} =
		min map { $cache->{yr_today}->datapoints->[$_]->temperature->celsius } ( 0 .. $#{ $cache->{yr_today}->datapoints } );
	$cache->{min_temp_tomorrow} = min map { $cache->{yr_tomorrow}->datapoints->[$_]->temperature->celsius }
		( 0 .. $#{ $cache->{yr_tomorrow}->datapoints } );
	my @weather24;
	for my $day ( $cache->{yr_today}, $cache->{yr_tomorrow} ) {
		foreach my $dp ( @{ $day->datapoints } ) {
			my $start = $dp->from->hms;
			push @weather24, $dp unless @weather24 > 24;
		}
	}
	$cache->{max_temp_24} = max map {$_->temperature->celsius} @weather24;
	$cache->{min_temp_24} = min map {$_->temperature->celsius} @weather24;
	$cache->{avg_temp_24} = sum(map {$_->temperature->celsius} @weather24) / @weather24;

	store $cache, $self->{config}{weather_cache_file};
	$self->{cache}        = $cache;
}

42;

