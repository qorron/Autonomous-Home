#!/usr/bin/perl

package tahoma;

use strict;
use warnings;
use feature ':5.24';
use Data::Dumper;
use URI::Encode qw(uri_encode uri_decode);
use JSON;
use Encode;
use LWP::UserAgent;
use HTTP::Response;
require HTTP::Headers;
use Text::Unidecode;
use UUID::Tiny ':std';


my $base_url = 'https://www.tahomalink.com/enduser-mobile-web/enduserAPI/';
my %default_headers = (
	Origin => '',
	'User-Agent' => '',
	Referer=> 'https://www.tahomalink.com/enduser-mobile-web/steer-html5-client/tahoma/',
);
 
sub new {
    my $that = shift;
    my $class = ref $that || $that;
    my %args = @_;
	die "username and password required!" unless ( defined $args{username} && defined $args{password} );
    my $self = {
		%args,
        };
    bless $self, $class;
}   

sub check_login {
	my ($self) = @_;
	if ($self->{login_ok} && (time - $self->{last_successful_access} < 60)) {
	} else {
		$self->login();
	}
}

sub login {
	my ($self) = @_;
	delete $self->{ua} if exists $self->{ua};
	my $ua = LWP::UserAgent->new( );
	$ua->cookie_jar( {} );
	$self->{ua} = $ua;
	my $headers = { 'Content-Type' => 'application/x-www-form-urlencoded; charset=UTF-8' };
	my $post_data = 'userId=' . uri_encode( $self->{username} ) . '&userPassword=' . uri_encode( $self->{password} );
	my $login_result = $self->xhr( 'POST', 'login', $headers, undef, $post_data );
	if ($login_result->{success} ) {
		$self->{login_ok}               = 1;
		$self->{last_successful_access} = time;
		return 1;
	} else {
		warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$login_result], ['login_result']);
		die 'login failed';
	}
	return;
}

sub get_setup {
	my ($self) = @_;
	my $setup = $self->xhr( 'GET', 'setup', undef, { _ => time }, undef );
	$self->{raw}{setup} = $setup;
}

sub get_action_groups {
	my ($self) = @_;
	my $action_groups = $self->xhr( 'GET', 'actionGroups', undef, { _ => time }, undef );
	$self->{raw}{action_groups} = $action_groups;
	my %ag_labels;
	my %ag_oids;
	my %ag_config;
	map {
		warn "Duplicate label: '$_->{label}', oid resolution may behave unexpectedly." if exists $ag_oids{ $_->{label} };
		warn "Duplicate name: '$_->{label}', oid resolution may behave unexpectedly."  if exists $ag_config{ _id( $_->{label} ) };
		$ag_labels{ $_->{oid} }          = $_->{label};
		$ag_oids{ $_->{label} }          = $_->{oid};
		$ag_config{ _id( $_->{label} ) } = $_->{oid};
	} @$action_groups;
	$self->{ag_oids} = \%ag_oids;
	$self->{ag_labels} = \%ag_labels;
	$self->{ag_config} = \%ag_config;
}

sub _id {

	# turns a string into something that can be used as a hash keys without quotes
	my $s = shift;
#	$s =~ s/([ÄäÖöÜüß])/$German_Characters{$1}/g;
	$s = fc( unidecode($s) );
	$s =~ s/[^a-z0-9]+/_/g;
	$s =~ s/^_+|_+$//;
	return $s;
}

sub perl_action_groups_config {
	my ($self) = @_;
	my $lines = join "\n", map { "\t $_ => '$self->{ag_config}{$_}'," } sort keys %{$self->{ag_config}};
	return <<EOT;
my %tahoma_action_groups = (
$lines
);
EOT
}

sub start_action_group {

	# exec/5a7e1567-ce40-480a-9d86-54185113cfe4
	my ($self, $scene) = @_;
	my $uuid = $self->resolve_uuid($scene);
	my $action_uuid = $self->xhr( 'POST', "exec/$uuid", undef, undef, undef );
	return $action_uuid->{execId};
}

sub start_action_group_at {

	# exec/schedule/5a7e1567-ce40-480a-9d86-54185113cfe4/1562166020136
	my ($self, $scene, $time) = @_;
	my $uuid = $self->resolve_uuid($scene);
	$time *= 1000; # tahoma uses milisecond precision
	my $action_uuid = $self->xhr( 'POST', "exec/schedule/$uuid/$time", undef, undef, undef );
	return $action_uuid->{triggerId};
}

sub resolve_uuid {
	my ($self, $scene) = @_;
	my $uuid;
	$self->get_action_groups() unless $self->{ag_labels};
	if ( is_uuid_string($scene) ) {
		warn "scene $scene not found, trying anyway"
			unless exists $self->{ag_labels}{$scene};
		$uuid = $scene;
	}
	elsif ( exists $self->{ag_config}{$scene} ) {
		$uuid = $self->{ag_config}{$scene};
	}
	elsif ( exists $self->{ag_oids}{$scene} ) {
		$uuid = $self->{ag_oids}{$scene};
	}
	else {
		die "scene $scene not found by name!";
	}
	return $uuid;
}

sub url_encode_hash {
	my ($self, $params) = @_;
	return '?'.join '&', map { uri_encode($_) . '=' . uri_encode( $params->{$_} ) } keys %$params;
}

sub xhr {
	my ($self, $method, $rel_url, $header, $get, $post) = @_;
	$self->check_login() unless $rel_url eq 'login';
	my $url = $base_url.$rel_url;
	my $encoded_post_data;
	if (defined $post && ref $post eq 'HASH') {
		$encoded_post_data = encode_utf8(encode_json($post));
	} elsif (defined $post) {
		$encoded_post_data = $post;
	}
	my $encoded_get_data;
	if (defined $get && ref $get eq 'HASH') {
		$encoded_get_data = $self->url_encode_hash($get);
		$url = $base_url.$rel_url.$encoded_get_data;
	}
	$header //= {};
	my $header_obj = HTTP::Headers->new(%default_headers, %$header);
	my $r = HTTP::Request->new($method, $url, $header_obj, $encoded_post_data);
	# warn $r->as_string;
	my $response = $self->{ua}->request($r);
	if ( $response->is_success ) {
		return decode_json($response->decoded_content);
	}
	else {
		delete $self->{login_ok};
		delete $self->{last_successful_access};
		warn $response->status_line, "\n";
		warn $response->decoded_content;
	}
	return;
}


<<BLA;

# login:
curl 'https://www.tahomalink.com/enduser-mobile-web/enduserAPI/login' -H 'Origin: https://www.tahomalink.com' -H 'DNT: 1' -H 'Accept-Encoding: gzip, deflate, br' -H 'Accept-Language: de-AT,de;q=0.9,en;q=0.8,en-US;q=0.7,en-GB;q=0.6' -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/75.0.3770.100 Safari/537.36' -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' -H 'Accept: */*' -H 'Referer: https://www.tahomalink.com/enduser-mobile-web/steer-html5-client/tahoma/' -H 'X-Requested-With: XMLHttpRequest' -H 'Cookie: JSESSIONID=2BB975803549DB3BA8E53BF2EDE79015' -H 'Connection: keep-alive' --data 'userId=xxyyy&userPassword=xxx' --compressed
# sets cookie

# get lsit of scenaries
curl 'https://www.tahomalink.com/enduser-mobile-web/enduserAPI/actionGroups?_=1562165721305' -H 'Cookie: JSESSIONID=8423A7C9CA442C95D1A3C7546ACE9C49' -H 'DNT: 1' -H 'Accept-Encoding: gzip, deflate, br' -H 'Accept-Language: de-AT,de;q=0.9,en;q=0.8,en-US;q=0.7,en-GB;q=0.6' -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/75.0.3770.100 Safari/537.36' -H 'Accept: */*' -H 'Referer: https://www.tahomalink.com/enduser-mobile-web/steer-html5-client/tahoma/' -H 'X-Requested-With: XMLHttpRequest' -H 'Connection: keep-alive' --compressed
every scenary has a uuid



# immediate execution of scenary uuid
curl 'https://www.tahomalink.com/enduser-mobile-web/enduserAPI/exec/5a7e1567-ce40-480a-9d86-54185113cfe4' -X POST -H 'Origin: https://www.tahomalink.com' -H 'DNT: 1' -H 'Accept-Encoding: gzip, deflate, br' -H 'Accept-Language: de-AT,de;q=0.9,en;q=0.8,en-US;q=0.7,en-GB;q=0.6' -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/75.0.3770.100 Safari/537.36' -H 'Accept: */*' -H 'Referer: https://www.tahomalink.com/enduser-mobile-web/steer-html5-client/tahoma/' -H 'X-Requested-With: XMLHttpRequest' -H 'Cookie: JSESSIONID=8423A7C9CA442C95D1A3C7546ACE9C49' -H 'Connection: keep-alive' -H 'Content-Length: 0' --compressed
# gets a uuid for the event
{"execId":"b8611c29-3626-5439-57a8-c16a7b6f981a"}

# query the uuid to get results
curl 'https://www.tahomalink.com/enduser-mobile-web/enduserAPI//exec/current/b8611c29-3626-5439-57a8-c16a7b6f981a?_=1562165721328' -H 'Cookie: JSESSIONID=8423A7C9CA442C95D1A3C7546ACE9C49' -H 'DNT: 1' -H 'Accept-Encoding: gzip, deflate, br' -H 'Accept-Language: de-AT,de;q=0.9,en;q=0.8,en-US;q=0.7,en-GB;q=0.6' -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/75.0.3770.100 Safari/537.36' -H 'Accept: */*' -H 'Referer: https://www.tahomalink.com/enduser-mobile-web/steer-html5-client/tahoma/' -H 'X-Requested-With: XMLHttpRequest' -H 'Connection: keep-alive' --compressed

      https://www.tahomalink.com/enduser-mobile-web/enduserAPI/exec/schedule/5c5a126e-bfa4-415c-b86c-0009967b3a6e/1562787611
curl 'https://www.tahomalink.com/enduser-mobile-web/enduserAPI/exec/schedule/5a7e1567-ce40-480a-9d86-54185113cfe4/1562166020136' -X POST -H 'Origin: https://www.tahomalink.com' -H 'DNT: 1' -H 'Accept-Encoding: gzip, deflate, br' -H 'Accept-Language: de-AT,de;q=0.9,en;q=0.8,en-US;q=0.7,en-GB;q=0.6' -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/75.0.3770.100 Safari/537.36' -H 'Accept: */*' -H 'Referer: https://www.tahomalink.com/enduser-mobile-web/steer-html5-client/tahoma/' -H 'X-Requested-With: XMLHttpRequest' -H 'Cookie: JSESSIONID=D6D0BAC90FA30EA7023C37715899139A' -H 'Connection: keep-alive' -H 'Content-Length: 0' --compressed

{"triggerId":"b8527543-3626-5439-57a8-c16a71067e48"}



BLA




42;

