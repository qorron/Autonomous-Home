#!/usr/bin/perl

package config;

use strict;
use warnings;
use feature ':5.20';
use Data::Dumper;
use FindBin;
use File::Slurp qw(slurp);
use Try::Tiny;


sub new {
	my $that = shift;
	my $class = ref $that || $that;

	# my %args = @_;
	my $self = { };
	bless $self, $class;
	$self->init();
	return $self;
}

sub init {
	my $self = shift;
	my $path = $FindBin::Bin;
	$self->{config_location} = '/etc/home_automation/main.pl';
	if ($path =~ m{^/home}) {
		$self->{dev} = 1;
		$self->{config_location} = "$FindBin::Bin/config/main.pl";
	}
	my %config;
	try {
		eval slurp $self->{config_location};
	}
	catch {
		die "Error parsing config file $self->{config_location} :\n$_";
	};
	my $class = ref $self;
	%$self = ( %$self, %config );
}





42;

