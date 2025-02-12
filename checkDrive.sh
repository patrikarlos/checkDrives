#!/bin/bash
##
## Drive reporter tool
## -------------------
## Usage; checkDrive <URL> <TOKEN> <IDSTRING> device1 device2 ... deviceN
##
## The tool will run smartctl <deviceK> and record various values.
## If the device is a spinning drive, it will do noting and move on.
## Otherwise, it will collect; model, serial, firmware, size, power on hours, and remaining usage(*).
## Once collected, it will then use <URL>, <TOKEN> and <IDSTRING> to send the data
## to an InfluxDB, for futher processing.
##
## (*) Sadly, there is not a standard for the devices. So, adaptations have to be made
## to suit the drives in question.
##
##

## Override LC_NUMERIC; force to C (consider changing to -j on smartctl)

LC_NUMERIC="C"

INFURL=$1
TOKENSTRING=$2
IDTAG=$3

shift 3

##echo "URL: $INFURL|$TOKENSTRING|$IDTAG"


for arg; do
##    echo "---$arg---"
    if [[ "$arg" == *"megaraid"* ]]; then 
	data=$(sudo smartctl -a -d "$arg")
    else
	data=$(sudo smartctl -a "$arg")
    fi

    ff=$(echo "$data" | grep 'Form Factor' | grep 'inches' | awk -F':' '{print $2}' | sed 's/ \{2,\}/ /g' )
    rr=$(echo "$data" | grep 'Rotation Rate' | awk -F':' '{print $2}' | sed 's/ \{2,\}/ /g' )

    if [[ "$rr" == *"rpm" ]]; then
	echo "Spinning rust, not interesting"
	continue;
    fi
   
    
    DevModel=$(echo "$data" | grep -E 'Device Model:|Model Number:' | awk -F':' '{print $2}' | sed 's/ \{2,\}/ /g' )
    SerNum=$(echo "$data" | grep 'Serial Number:' | awk -F':' '{print $2}' | sed 's/ \{2,\}/ /g' )
    FirmWare=$(echo "$data" | grep 'Firmware Version:' | awk -F':' '{print $2}' | sed 's/ \{2,\}/ /g' )
    UserCapacity=$(echo "$data" | grep -E 'User Capacity:|Total NVM Capacity|Size/Capacity:' | awk -F':' '{print $2}' | sed 's/ \{2,\}/ /g' | awk '{print $1}' | uniq )

    Power_on_Hours=$(echo "$data" |  grep -E 'Power_On_Hours|Power On Hours' | awk '{print $NF}' | sed 's/ \{2,\}/ /g' )
		     
    if [[ -z "$Power_on_Hours" ]]; then
	Power_on_Hours="NA"
    fi
    
    if [[ "$DevModel" == *"KINGSTON SEDC600M1920G"* ]]; then
	RemainingPercent=$(echo "$data" | grep "^231" | awk '{print $NF}');
    elif [[ "$DevModel" == *"INTEL SSDPEKNW010T8"* ]]; then
	RemainingPercent=$(echo "$data" | grep "^Available Spare:" | awk '{print $NF}');
    elif [[ "$DevModel" == *"Samsung SSD 980 PRO"* ]]; then
	RemainingPercent=$(echo "$data" | grep "^Available Spare:" | awk '{print $NF}');
    else
	echo "Unknown model"
	RemainingPercent="NA"
    fi

    DevModel=$(echo "$DevModel" | sed 's/ /_/g');
    UserCapacity=$(echo "$UserCapacity" | sed 's/,//g')
    FirmWare=$(echo "$FirmWare" | sed 's/ //g');
    SerNum=$(echo "$SerNum" | sed 's/ //g');
    Power_on_Hours=$(echo "$Power_on_Hours" | sed 's/,//g');

    RemainingPercent=$(echo "$RemainingPercent" | sed 's/\%//g');
    
    echo $(date --rfc-3339='ns')"|"$(hostname)"|$arg|$DevModel|$SerNum|$FirmWare|$UserCapacity|$Power_on_Hours|$RemainingPercent|"


    
    HOSTNAME=$(hostname)
    timestamp=$(date +%s)

    echo "string=|storage,host=$HOSTNAME,Device=$arg,Model=$DevModel,Serial=$SerNum,Firmware=$FirmWare,Capacity=$UserCapacity PowerOn=$Power_on_Hours,Remain=$RemainingPercent $timestamp|"
    
    curl --request POST \
	 "$INFURL/api/v2/write?org=main-org&bucket=storage&precision=s" \
	 --header "Authorization: Token $TOKENSTRING" \
	 --header "Content-Type: text/plain; charset=utf-8" \
	 --header "Accept: application/json" \
    	 --data-binary "storage,host=$HOSTNAME,Device=$arg,Model=$DevModel,Serial=$SerNum,Firmware=$FirmWare,Capacity=$UserCapacity PowerOn=$Power_on_Hours,Remain=$RemainingPercent $timestamp"
    echo ""
done
    


#src=$(grep -E "prComp|^231 |Power_On_Hours " CyberRange-smartctl-output-20240909.txt)
