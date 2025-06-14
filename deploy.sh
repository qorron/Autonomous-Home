#!/bin/bash

INSTALL_PATH='/usr/local/lib/home_automation/'
CONFIG_PATH='/etc/home_automation/'

# copy stuff from workspace to the final locations
# some parts are not yet ready to be released and thus commented out

# cp inverter.pl ${INSTALL_PATH}
# cp heat_collector.pl ${INSTALL_PATH}
cp heat_.pl ${INSTALL_PATH}heat_
cp zigbee_sensors.pl ${INSTALL_PATH}zigbee_sensors
cp mqtt_.pl ${INSTALL_PATH}
# cp AP_names.pl ${INSTALL_PATH}
# cp get_pressure.pl ${INSTALL_PATH}
cp shutter.pl ${INSTALL_PATH}
cp strom.pl ${INSTALL_PATH}
cp solar.pl ${INSTALL_PATH}
# cp prometheus.psgi ${INSTALL_PATH}
cp auto_ac.pl ${INSTALL_PATH}
cp get_weather.pl ${INSTALL_PATH}
cp sensors_collector.pl ${INSTALL_PATH}
cp mqtt_autoreset.pl ${INSTALL_PATH}
cp forecast_client.pl ${INSTALL_PATH}
cp forecast_worker.pl ${INSTALL_PATH}


cp lib/qmel.pm ${INSTALL_PATH}perl/
cp lib/get_weather.pm ${INSTALL_PATH}perl/
cp lib/get_openweather.pm ${INSTALL_PATH}perl/
cp lib/config.pm ${INSTALL_PATH}perl/

cp config/* ${CONFIG_PATH}
