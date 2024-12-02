# checkDrives

The tool will run smartctl <deviceK> and record various values.
If the device is a spinning drive, it will do noting and move on.
Otherwise, it will collect; model, serial, firmware, size, power on hours, and remaining usage(*).
Once collected, it will then use <URL>, <TOKEN> and <IDSTRING> to send the data
to an InfluxDB, for futher processing.


(*) Sadly, there is not a standard for the devices. So, adaptations have to be made
to suit the drives in question (hence the public Gitrepo).

