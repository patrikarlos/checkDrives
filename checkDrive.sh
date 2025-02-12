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

## SEt to 1 if to print debugging.
VERBOSE=0

shift 3

##echo "URL: $INFURL|$TOKENSTRING|$IDTAG"

if [[ $VERBOSE -eq 1 ]]; then
    echo "URL: $INFURL"
    echo "TOKEN: $TOKENSTRING"
    echo "IDTAG: $IDTAG"
fi

SUCCESSCNT=0;

for arg; do
    if [[ $VERBOSE -gt 1 ]]; then
	echo "---$arg---"
    fi
    if [[ "$arg" == *"megaraid"* ]]; then 
	data=$(sudo smartctl -a -d "$arg")
    else
	data=$(sudo smartctl -a "$arg")
    fi

    ff=$(echo "$data" | grep 'Form Factor' | grep 'inches' | awk -F':' '{print $2}' | sed 's/ \{2,\}/ /g' )
    rr=$(echo "$data" | grep 'Rotation Rate' | awk -F':' '{print $2}' | sed 's/ \{2,\}/ /g' )

    if [[ "$rr" == *"rpm" && $VERBOSE ]]; then
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

    if [[ $VERBOSE -eq 1 ]]; then
	echo $(date --rfc-3339='ns')"|"$(hostname)"|$arg|$DevModel|$SerNum|$FirmWare|$UserCapacity|$Power_on_Hours|$RemainingPercent|"
    fi

    
    HOSTNAME=$(hostname)
    timestamp=$(date +%s)

    if [[ $VERBOSE -eq 1 ]]; then
	echo "string=|storage,host=$IDTAG,Device=$arg,Model=$DevModel,Serial=$SerNum,Firmware=$FirmWare,Capacity=$UserCapacity PowerOn=$Power_on_Hours,Remain=$RemainingPercent $timestamp|"
    fi
    
    response=$(curl -s -w "%{http_code}" --request POST \
	 "$INFURL/api/v2/write?org=main-org&bucket=storage&precision=s" \
	 --header "Authorization: Token $TOKENSTRING" \
	 --header "Content-Type: text/plain; charset=utf-8" \
	 --header "Accept: application/json" \
    	 --data-binary "storage,host=$IDTAG,Device=$arg,Model=$DevModel,Serial=$SerNum,Firmware=$FirmWare,Capacity=$UserCapacity PowerOn=$Power_on_Hours,Remain=$RemainingPercent $timestamp"
	       )
    exit_status=$?
    http_code=$(tail -n1 <<< "$response")

    if [[ $VERBOSE -eq 1 ]]; then
	echo "hc=|$http_code|"
    fi
    
    if [ $exit_status -ne 0 ]; then
	echo "Curl had a problem; $exit_status, with $http_code and $response"
	exit;
    fi

    if [[ ! $http_code =~ ^2[0-9]{2}$ ]]; then
	echo "There is something wrong wit the request; $http_code and $response".
	exit;
    fi
    ((SUCCESSCNT++))
    
    
    
done

if [[ $VERBOSE -eq 1 ]]; then
    echo "Successfully sent $SUCCESSCNT devices."
fi

#src=$(grep -E "prComp|^231 |Power_On_Hours " CyberRange-smartctl-output-20240909.txt)
