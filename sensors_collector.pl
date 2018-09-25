#!/usr/bin/perl

# this collects sensor data around the house.
# it uses a lot of different systems to gather data from.
# TODO: put every one of them in a module so it can be made to fit someon elses needs too.

use strict;
use warnings;
use 5.020;
use Data::Dumper;
use Encode;
use POSIX;

my $time = time;
use JSON; # imports encode_json, decode_json, to_json and from_json.

use DBM::Deep;
use LWP::UserAgent;
use Text::Unidecode;

use lib qw( lib /usr/local/lib/home_automation/perl );
use config;

$Data::Dumper::Sortkeys = 1;

my $config = config->new();

our $debug = $ARGV[0];

our $translation;
our $munin;
our $host = $config->{host};



my $ua = LWP::UserAgent->new;


### Heaters ###
# electrical heaters controlled by a rasperry pi running IP-Symcon
# including room and floor temperature sensors for every room
# can be replaced with any room temperature sensor
# floor temp. sensors are used to determine the long term effects of the AC
# i.e. the air gets cooled down fast but the walls and floor follow slowly but keep the low temperature longer.
# this consists basically of recorded XHR calls from the web interface.
our $stuff;
our %subs;
our $id0 = 'ID0';

if ( exists $config->{host}{symcon} ) {
	my %power = %{$config->{heater}{power}};
	my $json_file = $config->{files}{heater_json_file};
	my %translation = %{$config->{heater}{translation}};

	$ua->agent(
		"Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/61.0.3163.100 Safari/537.36");
	$ua->default_header( Authorization => $config->{heater}{symcon_auth} );

	# Create a request
	my $req = HTTP::Request->new( POST => "http://$config->{host}{symcon}:3777/api/" );
	$req->content_type('application/json');
	$req->content(qq'{"jsonrpc":"2.0","method":"WFC_GetSnapshot","params":[$config->{heater}{symcon_root}],"id":$time}');

	# Pass request to the user agent and get a response back
	my $res = $ua->request($req);

	# Check the outcome of the response
	if ( $res->is_success ) {
		$stuff = decode_json $res->content;

		#warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$stuff], ['stuff']);

		my %all = (

			# 		id => $id0,
			# 		name => $stuff->{result}{objects}{$id0}{name},
			# 		subs => [],
		);

		# say join ' ', keys %{$stuff->{result}{objects}};
		for my $id ( keys %{ $stuff->{result}{objects} } ) {
			if ( exists $stuff->{result}{objects}{$id}{parentID} ) {

				# say "$id -> $stuff->{result}{objects}{$id}{parentID}";
				if ( exists $subs{"ID$stuff->{result}{objects}{$id}{parentID}"} ) {
					push @{ $subs{"ID$stuff->{result}{objects}{$id}{parentID}"} }, $id;
				}
				else {
					$subs{"ID$stuff->{result}{objects}{$id}{parentID}"} = [$id];
				}
			}
		}

		# warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\%subs], ['subs']);
		populate_tree( $id0, \%all );

		# warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\%all], ['all']);

		# until here we were generic

		my $rooms               = {};    # = $all{"R\x{e4}ume"};
		my $current_total_power = 0;

		# warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$all{Devices}{Sw1}], ['all']);
		for my $room ( grep {exists $all{$_}{Raumtemperatur}} keys %all) {

			# fca
			my $plain_room  = lc( unidecode($room) );
			my $switch_name = $room;
			$switch_name = $translation{$room} if exists $translation{$room};
			$rooms->{$plain_room} = $all{$room};
			$rooms->{$plain_room}{name} = decode( 'latin1', $room );
			$rooms->{$plain_room}{max_power} = $power{$room};
			# warn "$room $switch_name" unless exists $all{Devices}{Sw1}{$switch_name};
			$rooms->{$plain_room}{powered} = $all{$room}{HeatControlSwitch}{CurrentSwitch} // $all{$room}{'HeatControl PI'}{'Current Switch State'} // $all{$room}{'Heizung'}{'Current Switch State'};
			$rooms->{$plain_room}{floor_target} = $all{$room}{Heizung}{'Floor Target Temperature'} // $all{$room}{'HeatControl PI'}{'Floor Target Temperature'};
			$rooms->{$plain_room}{current_power} = $rooms->{$plain_room}{powered} ? $rooms->{$plain_room}{max_power} : 0;
			$current_total_power += $rooms->{$plain_room}{current_power};
		}

		compress_measurements($rooms);

		# some scripts still rely on the first implemenation of the sensor cache which was basically autogenerted perl code
		print Data::Dumper->Dump( [$rooms], ['rooms'] );
		say '$creation_time = ' . time . ';';
		my %outhash = ( creation_time => time );
		for my $rep (
			['Raumtemperatur',   'room'],
			['Bodentemperatur',  'floor'],
			['Absenktemperatur', 'set_low'],
			['Solltemperatur',   'set'],
			['Automatik',        'auto'],
			['Solartemperatur',  'set_solar'],
			['Status',           'state'],
			)
		{
			replace_key( $rooms, @$rep );
		}
		$outhash{rooms}         = $rooms;
		$outhash{current_power} = $current_total_power;
		my $json_fh;

		# newer ones use the json file.
		if (!$debug) {
			open $json_fh, '>', "$json_file.tmp" or die "failed to open $json_file.tmp $@";
			print $json_fh encode_json( \%outhash );
			close $json_fh;
			rename "$json_file.tmp", $json_file;
		}
	}
	else {
		warn $res->status_line, "\n";
	}
}

### gather data on electrical power generation ###
### fronius inverter ###
# http://www.fronius.com/en/photovoltaics/products/home/system-monitoring/open-interfaces/fronius-solar-api-json-
if ( exists $host->{solar} ) {
	my $solar_json_file = $config->{files}{solar_json_file};
	my $solar = get_powers();
	$solar->{creation_time} = time;
	my $solar_json_fh;
	if (!$debug) {
		open $solar_json_fh, '>', "$solar_json_file.tmp" or die "failed to open $solar_json_file.tmp $@";
		print $solar_json_fh encode_json($solar);
		close $solar_json_fh;
		rename "$solar_json_file.tmp", $solar_json_file;
	}
}


### measure the power flow to and from the grid
### B-Control energy manager ###
# https://www.tq-automation.com/content/download/10996/file/B-control_Energy_Manager_-_JSON-API.0101.pdf
if ( exists $host->{grid} ) {
	my $power_flow_json_file = $config->{files}{power_flow_json_file};
	my $power_balance_file = $config->{files}{power_balance_file};
	my $power_flow = get_power_flow();
	$power_flow->{creation_time} = time;
	my $power_flow_json_fh;
	if (!$debug) {
		open $power_flow_json_fh, '>', "$power_flow_json_file.tmp" or die "failed to open $power_flow_json_file.tmp $@";
		print $power_flow_json_fh encode_json($power_flow);
		close $power_flow_json_fh;
		rename "$power_flow_json_file.tmp", $power_flow_json_file;
	}

### power flow history ###
### B-Control energy manager ###
	# https://www.tq-automation.com/content/download/10996/file/B-control_Energy_Manager_-_JSON-API.0101.pdf
	# record power flow for the last hour
	# this is used to get an idea of how much power is currently available and ignore spikes in either direction
	my $db = DBM::Deep->new(
		file => $power_balance_file,
		type => DBM::Deep->TYPE_ARRAY
	);
	my $power = $power_flow->{'1-0:2.4.0*255'} || $power_flow->{'1-0:1.4.0*255'} * -1;
	$db->lock_exclusive();
	push @$db, { time => time, power => $power };
	while ( $db->[0]{time} < time - 3600 ) {
		shift @$db;
	}
	$db->unlock();
}
 

sub populate_tree {
	my ($id, $node_hashref) = @_;
	for my $sub_id (@{$subs{$id}}) {
		next if $sub_id eq $id0;
		#$node_hashref->{subs}{$sub_id} = {};
		if ( exists $stuff->{result}{objects}{$sub_id}{data}{value} ) {
			$node_hashref->{$stuff->{result}{objects}{$sub_id}{name}} = '' . $stuff->{result}{objects}{$sub_id}{data}{value};
		}
		elsif (exists $stuff->{result}{objects}{$sub_id}{data}{targetID}
			&& exists $stuff->{result}{objects}{"ID$stuff->{result}{objects}{$sub_id}{data}{targetID}"}{data}{value} )
		{
			$node_hashref->{$stuff->{result}{objects}{$sub_id}{name}} = '' . $stuff->{result}{objects}{"ID$stuff->{result}{objects}{$sub_id}{data}{targetID}"}{data}{value};
		} else {
			$node_hashref->{$stuff->{result}{objects}{$sub_id}{name}} = {};
			populate_tree($sub_id, $node_hashref->{$stuff->{result}{objects}{$sub_id}{name}});
		}
	}
}

sub replace_key {
	my ($hashref, $find, $replace) = @_;
	$hashref->{$replace} = delete $hashref->{$find} if exists $hashref->{$find};
	for my $key (keys %$hashref) {
		replace_key($hashref->{$key}, $find, $replace) if ref $hashref->{$key} eq 'HASH';
	}
}

sub compress_measurements {
	my ($hashref) = @_;
	for my $key (keys %$hashref) {
		if ( ref $hashref->{$key} eq 'HASH' ) {
			if (exists( $hashref->{$key}{Temperatur} ) ) {
				$hashref->{$key} = $hashref->{$key}{Temperatur};
			} else {
				compress_measurements($hashref->{$key});
			}
		}
	}
}


sub get_power_flow {
	my $ua         = get_agent();
	my $grid_data  = get_url( $ua, 'grid', '/mum-webservice/data.php' );
	return $grid_data;
}


### fronius inverter ###
# http://www.fronius.com/en/photovoltaics/products/home/system-monitoring/open-interfaces/fronius-solar-api-json-
# this is tailored for an inverter with 2 sets of solar panels facing in a different direction
sub get_powers {
	my $ua         = get_agent();
	my $today =  strftime("%F", (localtime(time)));
	my $solar_data = get_url( $ua, 'solar', "/solar_api/v1/GetArchiveData.cgi?Scope=System&StartDate=$today&EndDate=$today&Channel=TimeSpanInSec&Channel=Current_DC_String_1&Channel=Current_DC_String_2&Channel=Voltage_DC_String_1&Channel=Voltage_DC_String_2" );

	my $last = [sort {$b <=> $a} keys %{$solar_data->{Body}{Data}{'inverter/1'}{Data}{Current_DC_String_1}{Values}}]->[0] // 0;

	my $Current_DC_String_1 = $solar_data->{Body}{Data}{'inverter/1'}{Data}{Current_DC_String_1}{Values}{$last} // 0;
	my $Current_DC_String_2 = $solar_data->{Body}{Data}{'inverter/1'}{Data}{Current_DC_String_2}{Values}{$last} // 0;
	my $Voltage_DC_String_1 = $solar_data->{Body}{Data}{'inverter/1'}{Data}{Voltage_DC_String_1}{Values}{$last} // 0;
	my $Voltage_DC_String_2 = $solar_data->{Body}{Data}{'inverter/1'}{Data}{Voltage_DC_String_2}{Values}{$last} // 0;
	my $Power_DC_String_1 = $Current_DC_String_1 * $Voltage_DC_String_1;
	my $Power_DC_String_2 = $Current_DC_String_2 * $Voltage_DC_String_2;
	$solar_data = get_url( $ua, 'solar', '/solar_api/v1/GetInverterRealtimeData.cgi?Scope=System' );
	my $solar_power = $solar_data->{Body}{Data}{PAC}{Values}{1} // 0;
	return {
		AC_power            => $solar_power,
		Power_DC_String_1   => $Power_DC_String_1,
		Power_DC_String_2   => $Power_DC_String_2,
		Current_DC_String_1 => $Current_DC_String_1,
		Current_DC_String_2 => $Current_DC_String_2,
		Voltage_DC_String_1 => $Voltage_DC_String_1,
		Voltage_DC_String_2 => $Voltage_DC_String_2,
	};
}


sub get_url {
	my ($ua, $domain, $path) = @_;
	my $req = HTTP::Request->new( GET => "http://$host->{$domain}$path" );
	# say "http://$host->{$domain}$path";
	my $res = $ua->request($req);

	if ($res->is_success) {
		my $data = decode_json($res->content);
		update_auth($ua, $domain) and $res = $ua->request($req) and $data = decode_json($res->content) if exists $data->{authentication} && !$data->{authentication};
		return $data;
	}
	return {};
}

sub update_auth {
	my ($ua, $domain) = @_;;
	# Create a request
	# say 'update auth...';
	my $req = HTTP::Request->new( GET => "http://$host->{$domain}/start.php" );
	$ua->request($req);
}
sub get_agent {
	my $ua = LWP::UserAgent->new;
	$ua->agent(
		"Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/61.0.3163.100 Safari/537.36");

	$ua->cookie_jar( { file => "$ENV{HOME}/.cookies.txt", autosave =>1, ignore_discard=>1 } );
	return $ua;
}


### B-Control energy manager ###
# https://www.tq-automation.com/content/download/10996/file/B-control_Energy_Manager_-_JSON-API.0101.pdf
# this also adds some munin config along the way
sub fill_translation {
	$translation = {
		'1-0:1.4.0*255' => {
			'de'   => 'Wirkleistung Bezug',
			'en'   => 'Active power+',
			'munin' => 'power_import',
			'draw' => 'LINE1',
			'colour' => 'bb2211',
			'unit' => 'W',
		},
		'1-0:1.8.0*255' => {
			'de'   => 'Wirkenergie Bezug',
			'en'   => 'Active energy+',
			'unit' => 'Wh'
		},
		'1-0:10.4.0*255' => {
			'de'   => 'Scheinleistung Einspeisung',
			'en'   => 'Apparent power-',
			'unit' => 'VA'
		},
		'1-0:10.8.0*255' => {
			'de'   => 'Scheinenergy Einspeisung',
			'en'   => 'Apparent energy-',
			'unit' => 'VAh'
		},
		'1-0:13.4.0*255' => {
			'de'   => 'Leistungsfaktor',
			'en'   => 'Power factor',
			'unit' => '-'
		},
		'1-0:14.4.0*255' => {
			'de'   => 'Netzfrequenz',
			'en'   => 'Supply frequency',
			'unit' => 'Hz'
		},
		'1-0:2.4.0*255' => {
			'de'   => 'Wirkleistung Einspeisung',
			'en'   => 'Active power-',
			'munin' => 'power_export',
			'draw' => 'LINE1',
			'colour' => '22bb11',
			'unit' => 'W'
		},
		'1-0:2.8.0*255' => {
			'de'   => 'Wirkenergie Einspeisung',
			'en'   => 'Active energy-',
			'unit' => 'Wh'
		},
		'1-0:21.4.0*255' => {
			'de'   => 'Wirkleistung Bezug (L1)',
			'en'   => 'Active power+ (L1)',
			'munin' => 'power_import_l1',
			'draw' => 'AREA',
			'colour' => 'cc7711',
			'unit' => 'W'
		},
		'1-0:21.8.0*255' => {
			'de'   => 'Wirkenergie Bezug (L1)',
			'en'   => 'Active energy+ (L1)',
			'unit' => 'Wh'
		},
		'1-0:22.4.0*255' => {
			'de'   => 'Wirkleistung Einspeisung (L1)',
			'en'   => 'Active power- (L1)',
			'munin' => 'power_export_l1',
			'draw' => 'AREA',
			'colour' => '66dd11',
			'unit' => 'W'
		},
		'1-0:22.8.0*255' => {
			'de'   => 'Wirkenergie Einspeisung (L1)',
			'en'   => 'Active energy- (L1)',
			'unit' => 'Wh'
		},
		'1-0:23.4.0*255' => {
			'de'   => 'Blindleistung Bezug (L1)',
			'en'   => 'Reactive power+ (L1)',
			'unit' => 'var'
		},
		'1-0:23.8.0*255' => {
			'de'   => 'Blindenergy Bezug (L1)',
			'en'   => 'Reactive energy+ (L1)',
			'unit' => 'varh'
		},
		'1-0:24.4.0*255' => {
			'de'   => 'Blindleistung Einspeisung (L1)',
			'en'   => 'Reactive power- (L1)',
			'unit' => 'var'
		},
		'1-0:24.8.0*255' => {
			'de'   => 'Blindenergy Einspeisung (L1)',
			'en'   => 'Reactive energy- (L1)',
			'unit' => 'varh'
		},
		'1-0:29.4.0*255' => {
			'de'   => 'Scheinleistung Bezug (L1)',
			'en'   => 'Apparent power+ (L1)',
			'unit' => 'VA'
		},
		'1-0:29.8.0*255' => {
			'de'   => 'Scheinenergy Bezug (L1)',
			'en'   => 'Apparent energy+ (L1)',
			'unit' => 'VAh'
		},
		'1-0:3.4.0*255' => {
			'de'   => 'Blindleistung Bezug',
			'en'   => 'Reactive power+',
			'unit' => 'var'
		},
		'1-0:3.8.0*255' => {
			'de'   => 'Blindenergy Bezug',
			'en'   => 'Reactive energy+',
			'unit' => 'varh'
		},
		'1-0:30.4.0*255' => {
			'de'   => 'Scheinleistung Einspeisung (L1)',
			'en'   => 'Apparent power- (L1)',
			'unit' => 'VA'
		},
		'1-0:30.8.0*255' => {
			'de'   => 'Scheinenergie Einspeisung (L1)',
			'en'   => 'Apparent energy- (L1)',
			'unit' => 'VAh'
		},
		'1-0:31.4.0*255' => {
			'de'   => 'Stromstärke (L1)',
			'en'   => 'Current (L1)',
			'unit' => 'A'
		},
		'1-0:32.4.0*255' => {
			'de'   => 'Spannung (L1)',
			'en'   => 'Voltage (L1)',
			'unit' => 'V'
		},
		'1-0:33.4.0*255' => {
			'de'   => 'Leistungsfaktor (L1)',
			'en'   => 'Power factor (L1)',
			'unit' => '-'
		},
		'1-0:4.4.0*255' => {
			'de'   => 'Blindleistung Einspeisung',
			'en'   => 'Reactive power-',
			'unit' => 'var'
		},
		'1-0:4.8.0*255' => {
			'de'   => 'Blindenergy Einspeisung',
			'en'   => 'Reactive energy-',
			'unit' => 'varh'
		},
		'1-0:41.4.0*255' => {
			'de'   => 'Wirkleistung Bezug (L2)',
			'en'   => 'Active power+ (L2)',
			'munin' => 'power_import_l2',
			'draw' => 'STACK',
			'colour' => 'ee2211',
			'unit' => 'W'
		},
		'1-0:41.8.0*255' => {
			'de'   => 'Wirkenergie Bezug (L2)',
			'en'   => 'Active energy+ (L2)',
			'unit' => 'Wh'
		},
		'1-0:42.4.0*255' => {
			'de'   => 'Wirkleistung Einspeisung (L2)',
			'en'   => 'Active power- (L2)',
			'munin' => 'power_export_l2',
			'draw' => 'STACK',
			'colour' => '33ee11',
			'unit' => 'W'
		},
		'1-0:42.8.0*255' => {
			'de'   => 'Wirkenergie Einspeisung (L2)',
			'en'   => 'Active energy- (L2)',
			'unit' => 'Wh'
		},
		'1-0:43.4.0*255' => {
			'de'   => 'Blindleistung Bezug (L2)',
			'en'   => 'Reactive power+ (L2)',
			'unit' => 'var'
		},
		'1-0:43.8.0*255' => {
			'de'   => 'Blindenergie Bezug (L2)',
			'en'   => 'Reactive energy+ (L2)',
			'unit' => 'varh'
		},
		'1-0:44.4.0*255' => {
			'de'   => 'Blindleistung Einspeisung (L2)',
			'en'   => 'Reactive power- (L2)',
			'unit' => 'var'
		},
		'1-0:44.8.0*255' => {
			'de'   => 'Blindenergie Einspeisung (L2)',
			'en'   => 'Reactive energy- (L2)',
			'unit' => 'varh'
		},
		'1-0:49.4.0*255' => {
			'de'   => 'Scheinleistung Bezug (L2)',
			'en'   => 'Apparent power+ (L2)',
			'unit' => 'VA'
		},
		'1-0:49.8.0*255' => {
			'de'   => 'Scheinenergie Bezug (L2)',
			'en'   => 'Apparent energy+ (L2)',
			'unit' => 'VAh'
		},
		'1-0:50.4.0*255' => {
			'de'   => 'Scheinleistung Einspeisung (L2)',
			'en'   => 'Apparent power- (L2)',
			'unit' => 'VA'
		},
		'1-0:50.8.0*255' => {
			'de'   => 'Scheinenergie Einspeisung (L2)',
			'en'   => 'Apparent energy- (L2)',
			'unit' => 'VAh'
		},
		'1-0:51.4.0*255' => {
			'de'   => 'Stromstärke (L2)',
			'en'   => 'Current (L2)',
			'unit' => 'A'
		},
		'1-0:52.4.0*255' => {
			'de'   => 'Spannung (L2)',
			'en'   => 'Voltage (L2)',
			'unit' => 'V'
		},
		'1-0:53.4.0*255' => {
			'de'   => 'Leistungsfaktor (L2)',
			'en'   => 'Power factor (L2)',
			'unit' => '-'
		},
		'1-0:61.4.0*255' => {
			'de'   => 'Wirkleistung Bezug (L3)',
			'en'   => 'Active power+ (L3)',
			'munin' => 'power_import_l3',
			'draw' => 'STACK',
			'colour' => 'dd2299',
			'unit' => 'W'
		},
		'1-0:61.8.0*255' => {
			'de'   => 'Wirkenergie Bezug (L3)',
			'en'   => 'Active energy+ (L3)',
			'unit' => 'Wh'
		},
		'1-0:62.4.0*255' => {
			'de'   => 'Wirkleistung Einspeisung (L3)',
			'en'   => 'Active power- (L3)',
			'munin' => 'power_export_l3',
			'draw' => 'STACK',
			'colour' => '33dd77',
			'unit' => 'W'
		},
		'1-0:62.8.0*255' => {
			'de'   => 'Wirkenergie Einspeisung (L3)',
			'en'   => 'Active energy- (L3)',
			'unit' => 'Wh'
		},
		'1-0:63.4.0*255' => {
			'de'   => 'Blindleistung Bezug (L3)',
			'en'   => 'Reactive power+ (L3)',
			'unit' => 'var'
		},
		'1-0:63.8.0*255' => {
			'de'   => 'Blindenergie Bezug (L3)',
			'en'   => 'Reactive energy+ (L3)',
			'unit' => 'varh'
		},
		'1-0:64.4.0*255' => {
			'de'   => 'Blindleistung Einspeisung (L3)',
			'en'   => 'Reactive power- (L3)',
			'unit' => 'var'
		},
		'1-0:64.8.0*255' => {
			'de'   => 'Blindenergie Einspeisung (L3)',
			'en'   => 'Reactive energy- (L3)',
			'unit' => 'varh'
		},
		'1-0:69.4.0*255' => {
			'de'   => 'Scheinleistung Bezug (L3)',
			'en'   => 'Apparent power+ (L3)',
			'unit' => 'VA'
		},
		'1-0:69.8.0*255' => {
			'de'   => 'Scheinenergie Bezug (L3)',
			'en'   => 'Apparent energy+ (L3)',
			'unit' => 'VAh'
		},
		'1-0:70.4.0*255' => {
			'de'   => 'Scheinleistung Einspeisung (L3)',
			'en'   => 'Apparent power- (L3)',
			'unit' => 'VA'
		},
		'1-0:70.8.0*255' => {
			'de'   => 'Scheinenergie Einspeisung (L3)',
			'en'   => 'Apparent energy- (L3)',
			'unit' => 'VAh'
		},
		'1-0:71.4.0*255' => {
			'de'   => 'Stromstärke (L3)',
			'en'   => 'Current (L3)',
			'unit' => 'A'
		},
		'1-0:72.4.0*255' => {
			'de'   => 'Spannung (L3)',
			'en'   => 'Voltage (L3)',
			'unit' => 'V'
		},
		'1-0:73.4.0*255' => {
			'de'   => 'Leistungsfaktor (L3)',
			'en'   => 'Power factor (L3)',
			'unit' => '-'
		},
		'1-0:9.4.0*255' => {
			'de'   => 'Scheinleistung Bezug',
			'en'   => 'Apparent power+',
			'unit' => 'VA'
		},
		'1-0:9.8.0*255' => {
			'de'   => 'Scheinenergy Bezug',
			'en'   => 'Apparent energy+',
			'unit' => 'VAh'
		},
		'1-z:1.4.0*255' => {
			'de'   => 'Wirkleistung Bezug',
			'en'   => 'Active power+',
			'unit' => 'W'
		},
		'1-z:1.8.0*255' => {
			'de'   => 'Wirkenergie Bezug',
			'en'   => 'Active energy+',
			'unit' => 'Wh'
		},
		'1-z:11.4.0*255' => {
			'de'   => 'Stromstärke',
			'en'   => 'Current',
			'unit' => 'A'
		},
		'1-z:21.4.0*255' => {
			'de'   => 'Wirkleistung Bezug',
			'en'   => 'Active power+',
			'unit' => 'W'
		},
		'1-z:21.8.0*255' => {
			'de'   => 'Wirkenergie Bezug',
			'en'   => 'Active energy+',
			'unit' => 'Wh'
		},
		'1-z:29.4.0*255' => {
			'de'   => 'Scheinleistung Bezug',
			'en'   => 'Apparent power+',
			'unit' => 'VA'
		},
		'1-z:29.8.0*255' => {
			'de'   => 'Scheinenergie Bezug',
			'en'   => 'Apparent energy+',
			'unit' => 'VAh'
		},
		'1-z:31.4.0*255' => {
			'de'   => 'Stromstärke',
			'en'   => 'Current',
			'unit' => 'A'
		},
		'1-z:41.4.0*255' => {
			'de'   => 'Wirkleistung Bezug',
			'en'   => 'Active power+',
			'unit' => 'W'
		},
		'1-z:41.8.0*255' => {
			'de'   => 'Wirkenergie Bezug',
			'en'   => 'Active energy+',
			'unit' => 'Wh'
		},
		'1-z:49.4.0*255' => {
			'de'   => 'Scheinleistung Bezug',
			'en'   => 'Apparent power+',
			'unit' => 'VA'
		},
		'1-z:49.8.0*255' => {
			'de'   => 'Scheinenergie Bezug',
			'en'   => 'Apparent energy+',
			'unit' => 'VAh'
		},
		'1-z:51.4.0*255' => {
			'de'   => 'Stromstärke',
			'en'   => 'Current',
			'unit' => 'A'
		},
		'1-z:61.4.0*255' => {
			'de'   => 'Wirkleistung Bezug',
			'en'   => 'Active power+',
			'unit' => 'W'
		},
		'1-z:61.8.0*255' => {
			'de'   => 'Wirkenergie Bezug',
			'en'   => 'Active energy+',
			'unit' => 'Wh'
		},
		'1-z:69.4.0*255' => {
			'de'   => 'Scheinleistung Bezug',
			'en'   => 'Apparent power+',
			'unit' => 'VA'
		},
		'1-z:69.8.0*255' => {
			'de'   => 'Scheinenergie Bezug',
			'en'   => 'Apparent energy+',
			'unit' => 'VAh'
		},
		'1-z:71.4.0*255' => {
			'de'   => 'Stromstärke',
			'en'   => 'Current',
			'unit' => 'A'
		},
		'1-z:9.4.0*255' => {
			'de'   => 'Scheinleistung Bezug',
			'en'   => 'Apparent power+',
			'unit' => 'VA'
		},
		'1-z:9.8.0*255' => {
			'de'   => 'Scheinenergie Bezug',
			'en'   => 'Apparent energy+',
			'unit' => 'VAh'
		}
	};
	for my $key (keys %$translation) {
		next unless exists $translation->{$key}{munin};
		$munin->{$translation->{$key}{munin}} = {%{$translation->{$key}}{'draw', 'colour'}};
		$munin->{$translation->{$key}{munin}}{label} =  $translation->{$key}{de};
		$munin->{$translation->{$key}{munin}}{register} =  $key;
	}
	$munin->{power}       = { label => 'Current Total Power Balance', draw => 'LINE1', colour => '000000' };
	$munin->{power_solar} = { label => 'Erzeugte Leistung',           draw => 'LINE1', colour => '22bb00' };
	$munin->{power_usage} = { label => 'Verbrauchte Leistung',        draw => 'LINE1', colour => 'bb2200' };

}
