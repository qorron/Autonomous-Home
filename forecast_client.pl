#!/usr/bin/perl
use strict;
use warnings;
use 5.020;
use Data::Dumper;
use LWP::UserAgent ();
use List::Util qw(sum);
use Gearman::Client;
use JSON;
use File::Slurp qw(slurp);

use lib qw( lib . /usr/local/lib/home_automation/perl );
use config;

my $config = config->new();
my $heater = decode_json( slurp $config->{files}{heater_json_file} );

if ( $ARGV[0] && $ARGV[0] eq 'config' ) {
	my $deg = chr(176) . 'C';    # the ° sign in latin1...
	print <<BLA;
graph_title Outside Temperature
graph_args --base 1000 
graph_vlabel $deg
graph_category Enviroment
graph_info This graph monitors the current temperature outside, inside and the 24h forecast min. avg. and max.
graph_order Temperature max24h avg24h min24h avg_room avg_floor

Temperature.label Temperature
max24h.label Max. Temp. in 24h
avg24h.label Avg. Temp. in 24h
min24h.label Min. Temp. in 24h
avg_room.label Avg. Room Temp.
avg_floor.label Avg. Floor Temp.
BLA
}
else {

	my $ua = LWP::UserAgent->new;

	my $response = $ua->get('http://192.168.2.2/temperature');
	my $client   = Gearman::Client->new;
	$client->job_servers( '127.0.0.1', );
	my $max_temp_24_ref = $client->do_task( "forecast_stat", "max_temp_24", {} );
	my $avg_temp_24_ref = $client->do_task( "forecast_stat", "avg_temp_24", {} );
	my $min_temp_24_ref = $client->do_task( "forecast_stat", "min_temp_24", {} );

	if ( $response->is_success ) {
		my @rooms     = keys %{ $heater->{rooms} };
		my $avg_floor = sum( map { $heater->{rooms}->{$_}{floor} } @rooms ) / @rooms;
		my $avg_room  = sum( map { $heater->{rooms}->{$_}{room} } @rooms ) / @rooms;
		say 'Temperature.value ' . $response->decoded_content;
		say "max24h.value $$max_temp_24_ref";
		say "avg24h.value $$avg_temp_24_ref";
		say "min24h.value $$min_temp_24_ref";
		say "avg_room.value $avg_room";
		say "avg_floor.value $avg_floor";
	}
	else {
		warn $response->decoded_content;
		die $response->status_line;
	}
	$client->dispatch_background('forecast_refresh');
}
