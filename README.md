# The Autonomous-Home
A collection of stuff I put together to automate my home. this is not a complete home automation project with web ui, app, and everything and never will be. Instead this is a collection of scripts that aim to automate things in one's home so they run on their own and do not require any user interaction.
This requires much more fine grained control than simple "if this then that" mechanisms usually provided by home automation systems.
Also, device support is limited and there are devices which are supported by none of the major home automation frameworks. Let alone having one system to support all of them.

All this is not yet ready nor intendet to be a turnkey solution for your home.
It is highly Work in Progress.
I put this out in the public because I solved a lot of problems by implementing this and I want to provide others with a bit of a shortcut for their solutions.

Components:
- Weather forecast: gets weather forecast from yr.no and caches it for all scripts to use (get_weather.pl)
- Mitsubishi AC: perl module to fully control Mitsubishi AC units (qmel.pm).
- Sensor Collector: Collects and caches sensor data from local sensors so scripts can act upon that data
- Auto AC: turns the AC on if needed and there is enough solar electricity coming from the roof

Upcoming: (implemented but not yet ready for public release. e.g. config + code mixed together)
- MQTT Setup: ensures config on all of your devices running the Tasmota firmware
- MQTT Munin: Munin plugin that graph data like RSSI and Vcc of all modules running Tasmota
- Shutter Control: Closes (and opens) Velux roof shutters according to local weather forecast (temperature, cloudyness) and position of the sun to keep the rooms cool during summer.
