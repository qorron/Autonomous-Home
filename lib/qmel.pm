#!/usr/bin/perl

# inspired by: https://www.domoticz.com/forum/viewtopic.php?t=7496

package qmel;

use strict;
use warnings;
use 5.020;
use Data::Dumper;

#use HTTP::Request::Common qw(POST GET);
use HTTP::Headers;
use LWP::UserAgent;
use HTTP::Request;
use JSON;     

use config;

our @AC_MODES = qw(AC_COOL AC_HEAT AC_DRY AC_AUTO AC_FAN);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = (@AC_MODES, );
our @EXPORT_OK = qw(@AC_MODES);

use constant AC_COOL => 3;
use constant AC_AUTO => 8;
use constant AC_DRY  => 2;
use constant AC_HEAT => 1;
use constant AC_FAN  => 7;

our %flags = (
	Power          => 1,
	OperationMode  => 2,
	SetTemperature => 4,
	SetFanSpeed    => 8,
	VaneVertical   => 16,
);

sub new {
	my $class = shift;
	my %args  = @_;
	my $self  = {};
	bless $self, $class;

	# get serial numbers either from a room config
	map { $self->{sn}{$_} = $args{rooms}{$_}{serial} } keys %{ $args{rooms} } if $args{rooms};

	# or just take the serial hash
	$self->{sn} = $args{serial_numbers} if $args{serial_numbers};

	$self->read_config();
	return $self;
}


sub get_state {
	my ($self) = @_;
	my $state = $self->mel_get('User/ListDevices');
	$self->{raw_state} = $state;
	$self->parse_raw_state();
	return $state;
}

sub parse_raw_state {
	my ($self) = @_;
	my $devices;
	for my $entity ( @{ $self->{raw_state} } ) {
		$self->parse_devices( $entity->{Structure}{Devices}, { entity => $entity->{Name}, floor => '', area => '' } );
		for my $area ( @{ $entity->{Structure}{Areas} } ) {
			$self->parse_devices( $area->{Devices}, { entity => $entity->{Name}, floor => '', area => $area->{Name} } );
		}
		for my $floor ( @{ $entity->{'Structure'}{'Floors'} } ) {
			$self->parse_devices( $floor->{Devices}, { entity => $entity->{Name}, floor => $floor->{Name}, area => '' } );
			if ( exists $floor->{Areas} ) {
				for my $area ( @{ $floor->{Areas} } ) {
					$self->parse_devices( $area->{Devices}, { entity => $entity->{Name}, floor => $floor->{Name}, area => $area->{Name} } );
				}
			}
		}
	}
}

sub parse_structure {
	my ($self, $structure, $name_list) = @_;
	my $devices;
	my $name = 
	my @units = qw(Floors Areas);
	for my $floor	(@{${'Floors'}}) {
		#say $floor->{Name};
		for my $area (@{$floor->{Areas}}) {
		}
		
	}
}
sub parse_devices {
	my ($self, $device_list, $location) = @_;
	for my $device (@$device_list) {
		$self->{devices}{$device->{SerialNumber}}= $device;
		#say "device: $device->{DeviceName} entity: $location->{entity} floor: $location->{floor} area: $location->{area} sn: $device->{SerialNumber}";
		# warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$device], ['device']);
	}
}

sub get_device {
	my ($self, $name) = @_;
	return $self->{devices}{$self->serial($name)};
}

sub get_device_state {
	my ($self, $name) = @_;
	return $self->mel_get( 'Device/Get', { id => $self->get_device_id($name), buildingID => $self->get_building_id($name) } );
}

sub serial {
	my ($self, $name) = @_;
	return $self->{sn}{$name} if exists $self->{sn}{$name};
	return $name;
}

sub get_device_id {
	my ($self, $name) = @_;
	return $self->{devices}{$self->serial($name)}{DeviceID};
}
sub get_building_id {
	my ($self, $name) = @_;
	return $self->{devices}{$self->serial($name)}{BuildingID};
}

sub set_ac {
	my ($self, $name, $options) = @_;
# 	warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$options], ['options']);
	my $state = $self->get_device_state($name);
	my $flags = 0;
	$state->{HasPendingCommand} = 1;
	for my $option (keys %flags) {
		if (exists $options->{$option}) {
			$flags += $flags{$option};
			if ( ref $state->{$option} eq 'JSON::PP::Boolean' ) {
				$state->{$option} = ( $options->{$option} ? JSON::true : JSON::false );
			}
			else {
				$state->{$option} = $options->{$option};
			}
		}
	}
	$state->{EffectiveFlags} = $flags;
# 	warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$state], ['state']);
	return $self->mel_post('Device/SetAta', $state);
}



sub print_config {
	my ($self) = @_;
	for my $sn (keys %{$self->{devices}}) {
		say "'$self->{devices}{$sn}{DeviceName}' => $sn,";
	}
}

sub login {
	my ($self) = @_;

	my $login = $self->mel_post(
		'Login/ClientLogin',
		{   AppVersion       => $self->{app_version},
			Email            => $self->{email},
			Password         => $self->{password},
			Persist          => "true",
# 			CaptchaChallenge => "",
# 			CaptchaResponse  => "",
#			Language         => $self->{language},
		}
	);

	if ( $login->{LoginData}{ContextKey} ) {
		$self->{context_key} = $login->{LoginData}{ContextKey};
	}
	else {
		warn __PACKAGE__ . ':' . __LINE__ . $" . Data::Dumper->Dump( [\$login], ['login'] );
		die "Login failed";
	}
}




sub read_config {
	my ($self) = @_;

	$self->{config} = config->new();
	$self->{base_url}    = 'https://app.melcloud.com/Mitsubishi.Wifi.Client/';
	$self->{app_version} = "1.9.3.0";
	$self->{email}       = $self->{config}{ac}{email};
	$self->{password}    = $self->{config}{ac}{password};
	$self->{language} = $self->{config}{ac}{language};
}

sub mel_get {
	my ( $self, $end_point, $params ) = @_;
	if ($params) {
		my $url = '?';
		my @params = ();
		for my $param (keys %$params) { # TODO: input sanitation. let something else build this
			push @params, "$param=$params->{$param}";
		}
		$url .= join '&', @params;
		$end_point .= $url;
	}
	return melcloud_request($self, 'GET', $end_point);
}
sub mel_post {
	my ( $self, $end_point, $request ) = @_;
	return melcloud_request($self, 'POST', $end_point, $request);
}

sub melcloud_request {
	my ( $self, $method, $end_point, $request ) = @_;
	$method = uc($method);
	die 'supported methods: GET, POST' unless $method =~ /^(?:GET|POST)$/;
	die "need to login first!" unless $self->{context_key} || $end_point =~ /login/i;
	my $request_json = '';
	$request_json = encode_json($request) if $method eq 'POST';

	#Variables
	my $url = $self->{base_url} . $end_point;

	#   'https://app.melcloud.com/Mitsubishi.Wifi.Client/Device/SetAta';
	# set up the stuff
	my $ua = LWP::UserAgent->new();

	# Set our own user-agent string!
	$ua->agent("Domoticz Gysmo");
	my $req = HTTP::Request->new( $method => $url );
	$req->header( "X-MitsContextKey" => $self->{context_key} );
	if ($method eq 'POST') {
		$req->header( 'content-type'     => 'application/json' );
		$req->content($request_json);
	}

# 	warn $req->as_string;
	# Fire the cannon now !
	my $res = $ua->request($req);
	if ( $res->is_success ) {
		return decode_json( $res->content );
	}
	else {
		warn $res->status_line;
	}

}

1;
