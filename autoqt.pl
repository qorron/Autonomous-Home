#!/usr/bin/perl
use strict;
use warnings;
use 5.020;
use Data::Dumper;
use Path::Tiny;

use lib qw( lib /usr/local/lib/home_automation/perl );
use Net::MQTT::Simple;
use Net::Pushover;
use tahoma;
use config;

my $t = 'autoqt';

 
my $config = config->new();

# new object with auth parameters
my $push = Net::Pushover->new(
  token => $config->{keys}{pushover_app},
  user  => $config->{keys}{pushover_user},
);
 

my $mqtt = Net::MQTT::Simple->new( $config->{host}{mqtt} );
my $tahoma = tahoma->new( username => $config->{tahoma}{username}, password => $config->{tahoma}{password} );
$tahoma->login();


$mqtt->subscribe(
	'alert/+'         => sub { fail_shield( \&push, @_ ); },
	"$t/push/#"       => sub { fail_shield( \&push, @_ ); },
	"$t/tahoma/scene" => sub { fail_shield( \&tahom_scene, @_ ); },
	"ac/lockout/+"    => sub { fail_shield( \&ac_lockout, @_ ); },
);
$mqtt->run();


sub fail_shield {
	my ($sub, $topic, $message ) = @_;
	eval {
		&$sub($topic, $message );
	};
	if ($@ )  {
		warn "failed topic: $topic\nmsg: >>$message<<\n\n$@";
	}
}

sub ac_lockout {
	my ( $topic, $message ) = @_;
	path("/tmp/run_auto_ac")->touch;
}

sub tahom_scene {
	my ( $topic, $message ) = @_;
	my $uuid = $tahoma->start_action_group($message);
	say "scene $message started with id $uuid";
}

sub push {
	my ( $topic, $message ) = @_;
	if ($topic =~ m{(\w+)/(\w+)$}) {
		my ($severity, $headline) = (ucfirst $1, ucfirst $2);
		my $priority = {
			Emergancy => 2,
			Alert     => 1,
			Note      => -1,
			Debug     => -2,
			}->{$severity}
		// 0;
		my %emergancy_options = (
			retry  => 60,
			expire => 3600,
		);

		%emergancy_options = () unless $priority >= 2;
		# send a notification
		my $result = $push->message(
			title    => "$severity $headline",
			text     => "$severity $headline $message",
			priority => $priority,
			%emergancy_options,
		);
		if (!$result->{status} || $result->{errors}) {
			warn "errror(s) while sending push\n"
				. ( $result->{errors} && ref $result->{errors} eq 'ARRAY' ? join "\n", @{ $result->{errors} } : '' );
		} else {
			say "successfully sent $severity $headline $message";
		}
	}
}


