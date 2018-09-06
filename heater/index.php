<!DOCTYPE html>
<html>
    <head>
<script src="Chart.bundle.min.js"></script><!-- get this here: https://github.com/chartjs/Chart.js/releases and put it in the same directory -->
<script src="https://ajax.googleapis.com/ajax/libs/jquery/3.2.1/jquery.min.js"></script>
<style type="text/css">
form {
    display: inline;
}
</style>

	</head>
	<body bgcolor="black" text="white">
        <h1>
          <?php
       		echo "Heaters gonna heat";
          ?>
        </h1>
	<form name="params">
		<?php

			$outside_temps = array(
				"-30" => array(
					"outside_low" => -30,
					"outside_high" => -20,
					"floor_start" => -6, 
					"room_start" => -6, 
				),
				"-20" => array(
					"outside_low" => -20,
					"outside_high" => -10,
					"floor_start" => 0, 
					"room_start" => 0, 
				),
				"-10" => array(
					"outside_low" => -10,
					"outside_high" => 0,
					"floor_start" => 4, 
					"room_start" => 4, 
				),
				"-2" => array(
					"outside_low" => -2,
					"outside_high" => 12,
					"floor_start" => 8, 
					"room_start" => 8, 
				),
				"4" => array(
					"outside_low" => 4,
					"outside_high" => 14,
					"floor_start" => 10, 
					"room_start" => 10, 
				),
				"8" => array(
					"outside_low" => 8,
					"outside_high" => 18,
					"floor_start" => 12, 
					"room_start" => 12, 
				),
				"12" => array(
					"outside_low" => 12,
					"outside_high" => 22,
					"floor_start" => 15, 
					"room_start" => 15, 
				),
				"18" => array(
					"outside_low" => 18,
					"outside_high" => 28,
					"floor_start" => 20, 
					"room_start" => 20, 
				),
			);
			$algorithms = array(
				"r1" => array(
					"name" => "hysteresis",
					"params" => array (
							"delay" => 5,
						),
					),
				"r2" => array(
                    "name" => "PI Controller",
					"params" => array (
							"delay" => 1,
						),
                    ),
			);
			$fields = array(
				"section1" => "Start",
				"outside_low" => 4,
				"outside_high" => 4,
				"outside_mock" => "",
				"floor_start" => 10, 
				"room_start" => 10, 
				"room_jump" => 0, 
				"room_target" => 20, 
				"room_target_high" => 20, 
				"floor_max" => 25,
				"delay" => 5,
				"section2" => "Room Params",
				"floor_room_t" => 0.3, 
				"floor_outside_t" => 0.14, 
				"floor_increment" => 0.6, 
				"room_floor_t" => 0.19,
				"room_outside_t" => 0.13, 
				"section3" => "Controller Params",
				"r1_threshold" => 1,
				"r2_threshold" => 1,
				"r2_p" => 1,
				"r2_p_out" => 0.6,
				"r2_i" => 0.3,
				"r2_i_pos_max" => 6,
				"r2_i_neg_max" => 6,
			);
			$room_params = array(
				"demo" => array(
					"floor_room_t" => 0.3, 
					"floor_outside_t" => 0.14, 
					"floor_increment" => 0.6, 
					"room_floor_t" => 0.19,
					"room_outside_t" => 0.13, 
					"floor_max" => 25,
				),
				"bathroom" => array(
					"floor_room_t" => 0.3, 
					"floor_outside_t" => 0.14, 
					"floor_increment" => 0.6, 
					"room_floor_t" => 0.19,
					"room_outside_t" => 0.13, 
					"floor_max" => 30,
				),
				"livingroom" => array(
					"floor_room_t" => 0.35, 
					"floor_outside_t" => 0.16, 
					"floor_increment" => 0.4, 
					"room_floor_t" => 0.22,
					"room_outside_t" => 0.15, 
					"floor_max" => 25,
				),
			);

			?>Room presets: <?php
			foreach ($room_params as $name => $value) {
				?>
					<input type="button" value="<?php echo $name ?>" onclick="javascript: update_form_room(this.form, '<?php 
						echo $name;
					?>' ); update_graph(this.form);"/>
				<?php
			}
			?>
				Controller: <select name="algorithm" onchange="javascript: update_form_algorithm(this.form); update_graph(this.form);">
			<?php
			foreach ($algorithms as $name => $value) {
				?>
					<option value="<?php echo $name ?>" ><?php echo $value['name'] ?></option>
				<?php
			}
			?>
				</select> Outside temperature:
			<?php
			foreach ($outside_temps as $name => $value) {
				?>
					<input type="button" value="<?php echo $name ?>" onclick="javascript: update_form_outside(this.form, '<?php 
						echo $name;
					?>' ); update_graph(this.form);"/>
				<?php
			}

		?> : <input type="button" value="flat" onclick="javascript: this.form.outside_high.value = this.form.outside_low.value; update_graph(this.form);"> <?php
		?><input type="button" value="hold" onclick="javascript: this.form.room_start.value = this.form.room_target.value; this.form.floor_start.value = this.form.room_target.value; update_graph(this.form);"> : <?php
		?>Room: <input type="button" value="step" onclick="javascript: if (this.form.room_target.value == this.form.room_target_high.value) {this.form.room_target_high.value = parseFloat(this.form.room_target.value) + 1.0; this.form.room_target.value = this.form.room_target.value - 1; update_graph(this.form); } "> <?php
		?><input type="button" value="flat" onclick="javascript: if (this.form.room_target.value != this.form.room_target_high.value) {this.form.room_target.value = parseFloat(this.form.room_target.value) + 1.0; this.form.room_target_high.value = this.form.room_target.value; update_graph(this.form); } "><br><?php

			foreach ($fields as $name => $value) {
				if (preg_match('/^section/', $name)) {
					?><br><b><?php echo $value ?>:</b> <?php
				} else {
					$class = "";
					if (preg_match('/^(r\d)_/', $name, $matches)){
						$class = " class=\"$matches[1] algorithm\"";
					}
					?><span<?php echo $class?>><?php
					echo $name; ?>:&nbsp;<input name="<?php echo $name ?>" value="<?php echo $value ?>" size="4" /> </span><?php
				}
			}
		?><br>
		<input type="button" value="Compute" onclick="javascript: update_graph(this.form);"/>
	</form>switches: <span id="switches">0</span> overheats: <span id="overheat_counter">0</span> heater minutes: <span id="heater_minutes">0</span>
	<br><canvas id="myChart" width="600" height="265"></canvas>
<script>
var room_params = <?php echo json_encode($room_params) ?>;
var outside_temps = <?php echo json_encode($outside_temps) ?>;
var algorithms = <?php echo json_encode($algorithms) ?>;

// create initial empty chart
var ctx = "myChart";
var myChart = new Chart(ctx, {
  type: 'line',
  data: {
    datasets: [{
          label: 'room',
          data: [],
            backgroundColor: 'rgba(54, 162, 235, 0.2)',
            borderColor: 'rgba(54, 162, 235, 1)',
			pointHoverBackgroundColor: 'rgba(54, 162, 235, 1)',
            borderWidth: 1,
        }, {
          label: 'floor',
          data: [],
            backgroundColor: 'rgba(255, 99, 132, 0.2)',
            borderColor: 'rgba(255,99,132,1)',
			pointHoverBackgroundColor: 'rgba(255,99,132,1)',
            borderWidth: 1,
        }, {
          label: 'floor target',
          data: [],
            backgroundColor: 'rgba(33, 162, 33, 0.2)',
            borderColor: 'rgba(33, 162, 33, 1)',
			pointHoverBackgroundColor: 'rgba(33, 162, 33, 1)',
            borderWidth: 1,
        }, {
          label: 'power',
          data: [],
            backgroundColor: 'rgba(162, 162, 33, 0.2)',
            borderColor: 'rgba(162, 162, 33, 1)',
			pointHoverBackgroundColor: 'rgba(162, 162, 33, 1)',
            borderWidth: 1,
        }, {
          label: 'outside',
          data: [],
            backgroundColor: 'rgba(162, 162, 162, 0.1',
            borderColor: 'rgba(162, 162, 162, 1)',
			pointHoverBackgroundColor: 'rgba(162, 162, 162, 1)',
            borderWidth: 1,
        }, {
          label: 'room target',
          data: [],
            backgroundColor: 'rgba(162, 162, 162, 0',
            borderColor: 'rgba(212, 212, 212, 1)',
			pointHoverBackgroundColor: 'rgba(212, 212, 212, 1)',
            borderWidth: 1,
        }],
    labels: []
  },
  options: {
		defaultColor: "rgba(255,255,255,0.9)",
		defaultFontColor: '#fff',
		tooltips: {
			mode: 'index',
			intersect: false,
		},
		hover: {
			//mode: 'nearest',
			intersect: false
		},
        scales: {
            xAxes: [{
				//distribution: 'series',
            }],
            yAxes: [{
				gridLines: {
					color: 'rgba(255,255,255,0.5)',
					zeroLineColor: "rgba(255,255,255,0.9)",
				},
				ticks: {
					max: 32,
					fontColor: "#eee",
				},
				
				//distribution: 'series',
            }]
        }
    }
});


var update_form_room = function(form, room) {
	for (x in room_params[room]) {
		$("input[name='"+x+"']")[0].value = room_params[room][x];
	}
};
var update_form_outside = function(form, temp) {
	for (x in outside_temps[temp]) {
		$("input[name='"+x+"']")[0].value = outside_temps[temp][x];
		$("input[name='"+x+"']")[0].value = outside_temps[temp][x];
	}
};
var update_form_algorithm = function(form, name) {
	$('.algorithm').css('display', 'none');
	$('.'+form.algorithm.value).css('display', 'inline');
	for (x in algorithms[form.algorithm.value]['params']) {
		$("input[name='"+x+"']")[0].value = algorithms[form.algorithm.value]['params'][x];
	}
	
};
// logic to get new data
var update_graph = function(form) {
  $.ajax({
    url: `data.php?algorithm=${form.algorithm.value}&<?php
            foreach ($fields as $name => $value) {
				if (preg_match('/^section/', $name)) {
					// skip sections
				} else {
                	echo $name ?>=${form.<?php echo $name ?>.value}&<?php
				}
            }?>`,
    success: function(data) {
		$('#switches').text(data.switches);
		$('#heater_minutes').text(data.heater_minutes);
		$('#overheat_counter').text(data.overheat_counter);
      // process your data to pull out what you plan to use to update the chart
      // e.g. new label and a new data point
      
      // add new label and data point to chart's underlying data structures
      myChart.data.labels = data.labels;
      myChart.data.datasets[0].data = data.room;
      myChart.data.datasets[1].data = data.floor;
      myChart.data.datasets[2].data = data.floor_target;
      myChart.data.datasets[3].data = data.power;
      myChart.data.datasets[4].data = data.outside;
      myChart.data.datasets[5].data = data.room_target;
      
      // re-render the chart
      myChart.update();
    }
  });
};

update_form_algorithm (document.getElementsByName('params')[0]);
update_graph(document.getElementsByName('params')[0]);
</script>
	</body>
</html>
