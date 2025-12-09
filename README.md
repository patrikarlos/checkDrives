# checkDrives

The tool will run smartctl <deviceK> and record various values.
If the device is a spinning drive, it will do noting and move on.
Otherwise, it will collect; model, serial, firmware, size, power on hours, and remaining usage(*).
Once collected, it will then use <URL>, <TOKEN> and <IDSTRING> to send the data
to an InfluxDB, for futher processing.

URL is the complete URL to InfluxDB that will store the data, TOKEN is the token that grants
write access. IDSTRING is the host identifier string that will be associated with the
measurements. Hence, its important that its uniqe, otherwise data will be mixed. 

In the script there is a variable VERBOSE; set it to 1 for some debugging output. Usefull
during trails. Set it to 2 for a bit more output. If set to 0, no output will be produced
unless there are problems.


ATM; the tool relies on the stdout from smartctl, this can cause issues wrt. how numbers
are represented, i.e with ',' or ' ' between the numbers. If you have issues submitting the
results, verify that the values are represented as number without demarcations.
i.e. 1003 and not 1,003 or 1 003. Will eventually change how this is dealt with, to avoid it. 

(*) Sadly, there is not a standard for the devices. So, adaptations have to be made
to suit the drives in question (hence the public Gitrepo).

Example for Crontab running daily at 0600.

0 6 * * * <fullpath>/checkDrives/checkDrive.sh <url> <token> <idstring> dev1 dev2 ... devN

