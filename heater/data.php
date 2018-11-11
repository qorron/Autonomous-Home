<?php

$algorithm = $_GET['algorithm'];
$outside_low = $_GET['outside_low'];
$outside_high = $_GET['outside_high'];
$outside_mock = $_GET['outside_mock'];
$room_outside_t = $_GET['room_outside_t'];
$floor_start = $_GET['floor_start'];
$floor_room_t = $_GET['floor_room_t'];
$floor_outside_t = $_GET['floor_outside_t'];
$floor_increment = $_GET['floor_increment'];
$room_start = $_GET['room_start'];
$room_jump = $_GET['room_jump'];
$room_floor_t = $_GET['room_floor_t'];
$delay = $_GET['delay'];
$floor_max = $_GET['floor_max'];
$room_target = $_GET['room_target'];
$room_target_high = $_GET['room_target_high'];
$room_target_solar = $_GET['room_target_solar'];
$r1_threshold = $_GET['r1_threshold'];
$r2_threshold = $_GET['r2_threshold'];
$r2_p = $_GET['r2_p'];
$r2_p_out = $_GET['r2_p_out'];
$r2_i = $_GET['r2_i'];
$r2_i_pos_max = $_GET['r2_i_pos_max'];
$r2_i_neg_max = $_GET['r2_i_neg_max'];




// http://www.chartjs.org/samples/latest/charts/line/basic.html
$floor_temp = isset($floor_start) ? $floor_start : 30;
$room_temp = isset($room_start) ? $room_start : 18;
$floor_room_t = $floor_room_t ?: 0.4;
$room_floor_t = $room_floor_t ?: 0.4;


$floor_data = [];
$room_data = [];
$power_data = [];
$room_target_data = [];
$floor_target_data = [];
$outside_data = [];
$labels = [];
$tick = 1000;
$powered = false;
$r2i_i = 0;
$switches = 0;
$heater_minutes = 0;
$overheat_counter = 0;
$steps = 2880;
$day = 1440; # steps per day

$outside = $outside_low;
$outside_diff = $outside_high - $outside_low;

$outside_controller = 0; # outside visible to the controller to simulate the absense of a temperature sensor.
$room_target_controller = 0; # target temperature the controller has to reach. this will be set to $target or $target_high depending on the time.

for( $i = 0; $i<$steps; $i++ ) {

	$room_target_controller = ( is_solar($i) ? $room_target_solar : ( is_high($i) ? $room_target_high : $room_target) );

	$outside = $outside_low + ((1+cos(2*M_PI*$i/$day - M_PI*1.166)) * $outside_diff/2);
	$outside_controller = ($outside_mock == "" ? $outside : $outside_mock );

	if ($room_jump != 0 && $i == intval ($steps/2)) {
		$room_temp = $room_jump;
	}
	$change = false;
	$tick++;

	// simulation
	if ($powered) {
		$floor_temp += $floor_increment;
	}
	$room_outside_delta = ($room_temp - $outside) * pow(M_E, -1 *(1/$room_outside_t));
	$floor_outside_delta = ($floor_temp - $outside) * pow(M_E, -1 *(1/$floor_outside_t));
	$floor_delta = ($floor_temp - $room_temp) * pow(M_E, -1 *(1/$floor_room_t));
	$room_delta = ($room_temp - $floor_temp) * pow(M_E, -1 *(1/$room_floor_t));
	$floor_temp -= $floor_delta+$floor_outside_delta;
	$room_temp -= $room_delta+$room_outside_delta;

	// build graph data
	$floor_data[] = $floor_temp;
	$room_data[] = $room_temp;
	$power_data[] = ($powered ? 3 : 0 );
	$outside_data[] = $outside;
	$room_target_data[] = $room_target_controller;
	$labels[] = sprintf("%d:%02d",   floor($i/60), $i%60); 


	// run the algorithms to decide if the heater should be turned on or off
 	//file_put_contents('php://stderr', print_r("tick: ".$tick."\n", TRUE));
	if ($algorithm == "r1") {
		$powered_new =    stock($room_temp, $floor_temp, $outside_controller, $powered, $tick, $delay, $room_target_controller, $r1_threshold);
	} elseif ($algorithm == "r2") {
		$powered_new = adaptive($room_temp, $floor_temp, $outside_controller, $powered, $tick, $delay, $floor_max, $room_target_controller, $r2_threshold, $r2_p, $r2_p_out, $r2_i, $r2_i_pos_max, $r2_i_neg_max, $r2i_i, $floor_target_data);
	}


	// failsave
	if ($powered_new && $floor_temp > $floor_max) {
 		//file_put_contents('php://stderr', print_r("OVERHEAT! turning off!\n", TRUE));
		$overheat_counter++;
		$powered_new = false;
	}

	//file_put_contents('php://stderr', print_r("power is: ".$powered." will change to ".$powered_new."\n", TRUE));
	$change = ($powered xor $powered_new);
	if ($change) {
		//file_put_contents('php://stderr', print_r("change detected\n", TRUE));
		$tick = 0;
		$switches++;
	}
	if ($powered_new) {
		$heater_minutes++;
	}
	$powered = $powered_new;
}

$data = [
	"floor" => $floor_data,
	"room"  => $room_data,
	"power"  => $power_data,
	"room_target" => $room_target_data,
	"floor_target" => $floor_target_data,
	"outside" => $outside_data,
	"labels" => $labels,
	"switches" => $switches,
	"heater_minutes" => $heater_minutes,
	"overheat_counter" => $overheat_counter,
];
header('Content-Type: application/json');
echo json_encode($data);


function stock($room_temp, $floor_temp, $outside, $powered, $tick, $delay, $r1_target, $r1_threshold) {
# 	file_put_contents('php://stderr', print_r("room_temp: ".$room_temp." floor_temp: ".$floor_temp." outside: ".$outside." powered: ".$powered." tick: ".$tick." delay: ".$delay." r1_on: ".$r1_on." r1_off: ".$r1_off."\n", TRUE));
	$r1_on  = $r1_target - $r1_threshold;
	$r1_off = $r1_target + $r1_threshold;

	$powered_new = $powered;
	if (!$powered && $room_temp < $r1_on && $tick > $delay ) {
		$powered_new = true;
	}
	if ($powered && $tick > $delay && ($room_temp > $r1_off )) {
		$powered_new = false;
	}

    return $powered_new;
}

/*
how it works:
instead of turning the heater off and on according to the room temperature, we calculate the temperature the floor must have for the room to reach the desired temperature.
then we turn the heater on and off according to the floor temperature.

measurements:
$room_temp, $floor_temp, $outside : measured temperatures
	in absence, $outside can be set to a static value e.g. 4

general persistent variables:
these shall be kept persistent between each time the script is executed. ideally they are persistent even if the controller reboots.
$powered : the current state of the heater relay. used to ensure the minimum $delay between state changes is respected.
$tick : a counter/imaginary time unit to simulate the passing of time so we can simulate a day in a few microseconds.
	a $tick minute. so, for the current parameters to work nicely, this algorithm should be called every minute.
	also, $tick must be reset to 0 after the $powered state of the relay has been changed.

general parameters:
$delay : munimum ticks/minutes the relay must stay in one state to prevent high switching frequewncies.
$floor_max : maximum temperature of the floor
$r2_target : the target room temperature

PI-controller specific parameters:
$r2_threshold : default=1 maximum hysteresis value the floor temperature is allowed to deviate from the calculated target floor temperature. 
	e.g. $r2_threshold = 1, $floor_target = 24, $floor_temp will be allowed to oscilate between 23 and 25
	decrease this to restrict floor temperature oscilation amplitude.
	increase this to have fewer switches per hour
$r2_p : default=1 room temperature proportional factor. determines how strong the difference between the $r2_target and the $room_temp contributes to the target floor temp.
$r2_p_out : default=0.6 outside temperature proportional factor. determines how strong the difference between the $r2_target and the $outside contributes to the target floor temp.
$r2_i :  default=0.3 factor to determine how fast the $room_diff is integrated into the $r2i_i
$r2_i_pos_max : default=6 limits for $r2i_i
$r2_i_neg_max : default=6 this is to reduce oscilations at a cold start

PI-controller specific persistent variables:
these will be changed in the algorithm and shall be kept persistent between each time the script is executed. ideally they are persistent even if the controller reboots.
$r2i_i : initialize outside with 0. the integral part of the controller. it grows while the $room_temp is below the $r2_target and gets smaller if the $room_temp is above the $r2_target
	having this ensures the controller adapts itself to any circumstances
$target_data : initialize as empty array. this is where the $floor_target is recored to be graphed in the simulation. this and the line adding a temperature are only needed for the simulation and must be removed in the production controller. failing to do so will give you a memory leak!

returns boolean : the new state of the heater relay

*/

function adaptive($room_temp, $floor_temp, $outside, $powered, $tick, $delay, $floor_max, $r2_target, $r2_threshold, $r2_p, $r2_p_out, $r2_i, $r2_i_pos_max, $r2_i_neg_max, & $r2i_i, & $target_data) {
	$powered_new = $powered;

	// calculate diffs
	$out_diff = $r2_target - $outside;
	$room_diff = $r2_target - $room_temp;

	// clamp down the integrative part to prevent wild oscilations
	$r2_i_pos_max = min((1+2*abs($room_diff)), $r2_i_pos_max);
	$r2_i_neg_max = min((1+2*abs($room_diff)), $r2_i_neg_max);

	// ingetrate	
	$r2i_i += ($room_diff* $r2_i);

	//apply limits
	$r2i_i = min($r2i_i, $r2_i_pos_max);
	$r2i_i = max($r2i_i, -1 * $r2_i_neg_max);

	// put it all together as an offset to the target temperature
	// I'm using the sqrt of the diffs here because the controller behaves much nicer that way.
	// big diffs at startup are dampened but it still reacts snappy to small deviations
	$diff = (sign($out_diff) * sqrt(abs($out_diff)) * $r2_p_out ) // rise the bias for cooler outside temperatures
		+ (sign($room_diff) * sqrt(abs($room_diff)) * $r2_p) // add room temperature error
		+ $r2i_i; // this stabilizes the room temp within some tnths of a degree aroung the target.

	// calculate the floor target and apply the maximum floor temp cap
	// $floor_temp is allowed to oscilate around $floor_target with +/- $r2_threshold
	// so $floor_target stays $r2_threshold degrees clear of $floor_max
	$floor_target = $r2_target + $diff;
	// use a narrower temp interval if we desperately need a higher floor temperature
	if ($floor_target > $floor_max) {
		$r2_threshold /=2;
	}
	$floor_target = min( $floor_target, ( $floor_max - $r2_threshold ) );

	// we graph tzhe floor target as welll to see what's going on
 	$target_data[] = $floor_target; // REMOVE THIS IN PRODUCTION!

	// since we cannot dim or PWM anything, a simple hysteresis controller should do the job
	if (!$powered && $tick > $delay && $floor_temp < ($floor_target - $r2_threshold)) {
		$powered_new = true;
	}
	if ($powered && $tick > $delay && ($floor_temp > ($floor_target + $r2_threshold ))) {
		$powered_new = false;
	}

    return $powered_new;
}

// signunm function. returns -1 if $i < 0, +1 if $i > 0 and 0 if $i == 0
function sign($i) {
	return $i <=> 0;
}

function is_high($i) {
	$i %= 1440;
	$i = intval($i/60);
	return ($i >= 7 && $i < 10) || ($i >= 17 && $i < 23);
}

function is_solar($i) {
	$day_min = $i%1440;
	$day_h = intval($day_min/60);
	if ($i < 1440) { # let day 1 be a shady day with a lot of noise
		return ($day_h >= 11 && $day_h < 16 && ($i%6 > 2));
	} else { # day 2 shall be a sunny day with an uninterrupted period of solar power
		return ($day_h >= 11 && $day_h < 16);
	}
	$i %= 1440;
	$i = intval($i/60);
	return ($i >= 7 && $i < 10) || ($i >= 17 && $i < 23);
}

?>
