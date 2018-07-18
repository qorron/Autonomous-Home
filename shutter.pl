#!/usr/bin/env perl

# this uses solar position data and weather forecasts to determeine on when to close and open roof window shutters to mitigate day time heat ingression into the rooms.
# shutters are controlled via a somfy tahome box which is controlled by fhem, a perl based home automation system which I do not yet fully understand.
# the positions are configured as scenarios in the tahoma box, fhem just calls those.
# usage:
# shutter.pl <tomorrow> <doit>
# tomorrow: 0 use today, 1 use tomorrow to operate on data of a full day.
# doit: has to be 1 to actually execute something.

use strict;
use warnings;
use 5.020;
use Data::Dumper;

use Time::ParseDate;
use POSIX qw(strftime);

use Astro::Sunrise qw( :constants sunrise sun_rise sun_set);

# use Weather::YR;
#use DateTime::TimeZone;
use DateTime;

use lib qw( . /usr/local/lib/home_automation/perl );
use get_weather;
use config;


my $tz = DateTime::TimeZone->new( name => 'local');

my $config = config->new();

my $latitude              = $config->{latitude};
my $longitude             = $config->{longitude};
my $temperature_threshold = $config->{shutter}{temperature_threshold};
my $altitude              = $config->{shutter}{altitude};
my $min_bright_hours      = $config->{shutter}{min_bright_hours};
my $cloudiness_threshold  = $config->{shutter}{cloudiness_threshold};
my $action                = 'retval';


my ($tomorrow, $doit) = @ARGV;
$tomorrow //= 0;

my $weather = get_weather->new(max_age => 1800);

my $today = ($tomorrow ? 'tomorrow' : 'today'); # 1: tomorrow, 0: today (for late night coding)
my $day = $weather->{cache}{"yr_$today"};
say $day->date . ':';
say ' ' x 4 . 'Temperature = ' . $weather->{cache}{"max_temp_$today"};
$altitude = $config->{shutter}{hot_day_altitude} if $weather->{cache}{"max_temp_$today"} > $config->{shutter}{hot_day_temperature};
my $sun_rise = sun_rise(
	{   lon     => $longitude,
		lat     => $latitude,
		alt     => $altitude,
		precise => 0,
		offset  => $tomorrow,
		polar   => $action
	}
);
my $sun_set = sun_set(
	{   lon     => $longitude,
		lat     => $latitude,
		alt     => $altitude,
		precise => 0,
		offset  => $tomorrow,
		polar   => $action
	}
);
my $qr_time = qr<^(\d\d):\d\d$>;
my ($first_hour, $last_hour);
if (   $sun_rise =~ /$qr_time/
	and $first_hour = $1
	and $sun_set =~ /$qr_time/
	and $last_hour = $1 )
{

	my @hours = map {"$_:00:00"} ($first_hour .. $last_hour);
	# say join "\n", @hours;
	my $bright_hours = 0;
    foreach my $dp ( @{$day->datapoints} ) {
		my $start = $dp->from->hms;
		next unless $start ~~ @hours;
		my $bright = $dp->cloudiness->percent < $cloudiness_threshold;
        say ' ' x 4 . 'Cloudiness: ' . $dp->cloudiness->percent . " $start ".($bright ? 'bright' : 'clouds');
		$bright_hours++ if $bright;
    }
	say "Sun high begins at $sun_rise and ends at $sun_set. We'll get $bright_hours hours of sunshine."; 
	my $now = time;
	if ( $weather->{cache}{"max_temp_$today"} > $temperature_threshold ) {
		if ( $bright_hours >= $min_bright_hours ) {
			# perl -MTime::ParseDate -MPOSIX -E'say time; say strftime "%c", gmtime(); say parsedate(strftime "%c", gmtime() )'
			# 
			$sun_rise = parsedate( ( $tomorrow ? 'tomorrow ' : '' ) . $sun_rise);# , ZONE => 'CEST' );
			$sun_set  = parsedate( ( $tomorrow ? 'tomorrow ' : '' ) . $sun_set); #, ZONE => 'CEST' );
			my $closed = $sun_set - $sun_rise;
			if ( $closed >= 3600 ) {
				my %offset = (
					down => 1000 * ( $sun_rise - $now ),
					up   => 1000 * ( $sun_set - $now ),
				);
				say strftime('%Y-%m-%d %X %Z',gmtime());
				my $offset;
				for my $preset ( keys %{ $config->{shutter}{presets} } ) {
					next unless $preset =~ /^day_/;    # skip night shutters for now.
					next unless $config->{shutter}{presets}{$preset};
					my $motion;
					
					if ( $preset =~ /(up|down)$/ ) {
						$motion = $1;
						$offset = $offset{$motion} + $config->{shutter}{offsets}{$preset};
						my $dt = DateTime->from_epoch( epoch => ( $now + ( $offset / 1000 ) ) );
						$dt->set_time_zone($tz);
						say "$sun_rise $sun_set $preset at " . $dt->datetime. " ". $dt->time_zone_long_name()." ".$dt->time_zone_short_name();
						
						
						execute("/opt/fhem/fhem.pl 7072 'set $config->{shutter}{presets}{$preset} startAt $offset'");
					}
				}
			}
			else {
				say "closed time is less than an hour, not closing";
			}
		} else {
			say "not closing due to cloudyness";
		}
	}
	else {
		say "Temp too low.";
	}
}

sub execute {
	my $command = shift;
	say $command;
	say `$command` if $doit;
}
