#!/usr/bin/perl
use strict;
use warnings;
use 5.020;
use Data::Dumper;

use Gearman::Worker;

use lib qw( lib . /usr/local/lib/home_automation/perl );
use get_weather;

my $launch_time = time;

my $weather = get_weather->new( max_age => 1600, verbode => 1 ); # seconds

my $worker = Gearman::Worker->new;
$worker->job_servers( '127.0.0.1',);
 
$worker->register_function(forecast_stat => sub {
    my $job = shift;
	my $stat_name = $job->arg;
	say "job: $stat_name";
	my $data = $weather->{cache}{$stat_name};
# 	$worker->send_work_data($job, $data);
# 	$worker->send_work_complete($job, 1);
# 	sleep 3;
	$data;
  }
);
$worker->register_function(forecast_refresh => sub {
    my $job = shift;
	say 'refresh';
	$weather->refresh();
	1;
  }
);
 
$worker->work(
#   on_start => sub {
#     my ($jobhandle) = @_;
#     ...
#   },
#   on_complete => sub {
#     my ($jobhandle, $result) = @_;
#     ...
#   },
  on_fail => sub {
    my ($jobhandle, $err) = @_;
    say "err: '$jobhandle' '$err'";
  },
#   stop_if => sub {
#     my ($is_idle, $last_job_time) = @_;
#     # stop idle worker
#     return ;
#   },
) while 1;


