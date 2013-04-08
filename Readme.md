telemetry tag adder
=============== 
Ruby version of the [python script](https://github.com/adobe/telemetry-utils) to enable advanced telemetry data for profiling SWFs

## add_telemetry.rb

Adds the EnableTelemetry tag to a SWF file for use with Adobe Scout.

Run this script on your SWF to make it generate advanced telemetry, which is
needed for the ActionScript Sampler, Stage3D Recording, and other features.

This script is provided as a last resort. If possible, you should compile your
application with the -advanced-telemetry option.

### Instructions

1. You need Ruby installed (tested on Ruby 1.9.3)
2. Run the command:
    ruby add_telemetry.rb swf_file [password]


If password is provided, advanced telemetry will only be visible if a matching 
password is entered in Adobe Scout. 
