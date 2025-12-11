# checkDrives

The tool will run smartctl <deviceK> and record; Capacity, Firmware, Serial Number,
Power On Hours and Remaining Percentage. This is a complement to other smartctl tools, like
smartctlexporter (Prometheus). This targets SSD and NVME explicity. It does not care about
spinning drives. It then reports the data to an InfluxDB (bucket 'storage'). 

As each vendor/model may have different parameters, its not as easy to treat all the same.
So, the system as a file (models) where the supported models are defined. For now, the
model indicates HOW Remaining Percentage will be estimated. Sadly, its hard coded in the
script (checkDrives.sh). This should change, so the parameters are defined in the model
file, as to simplify support for new models.

The script either from command line, or a configuration file. If no arguments are provided, the
default, /etc/default/checkdrives.cfg, is read. All parameters can be overriden by command line
arguments.

In the config file, you find the INFURL that is the URL to the Influx DB. TOKENSTRING is the
token that grants access. IDTAG is the name you want the data to be associated with. Strongly
recommed to set this to the HOST name of your device.Its important that its uniqe, otherwise
data will be mixed. 

In the script there is a variable VERBOSE; set it to 1 for some debugging output. Usefull
during trails. Set it to 2 for a bit more output. If set to 0, no output will be produced
unless there are problems.

In the config file, there is a variable DEVICES. This is were you should define the devices you
want the script to check. To identify the devices, there is a support script; identifyDrives.sh.
This will identify all(hopefully) SSD and NVEM devices, and match/compare if they are found in
the models file. You would then use the device name (/dev/sda, /dev/nvme0n1) as the name used in
the config file, or as an argument to the script. Those that are listed in 'unmatched' are
detected, but do not match any of the currently supported models. 

The solution can be installed as a systemd service, checkDrives.{service,timer}. This will run
every hour. Alternative, configure the script to run from a cronjob. 

The 'Makefile', can be used to install, and uninstall, the service.

If you run the script with -x, it will execute all parts with the exception of sending the http
request. Used in conjunction with -v 2 gives you a lot of debugging information.

Recommended procedure,
1. Identify the devices. 
./identifyDrives.sh

2. Create a local config file
cp checkDrives_template.cfg my.cfg

3. populate with devices, ignore InfluxDB parts for now.

4. Check execution
./checkDrives.sh -c my.cfg -v 2 -x

5. Verify that you see "Successfully sent X devices", were X represents the number of devices you
provided in the my.cfg file.

6. If ok, install 'sudo make install'

7. Adjust /etc/default/checkdrives.cfg to match your devices and InfluxDB.

Next would be to configure visualization, but that's out of scope. 



