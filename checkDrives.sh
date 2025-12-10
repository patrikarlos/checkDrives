#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/default/checkdrives.cfg"

cli_INFURL=""
cli_TOKENSTRING=""
cli_IDTAG=""
cli_VERBOSE=""
cli_TESTING=""



usage() {
  cat <<EOF
Usage: $0 [-c CONFIG] [-u URL] [-t TOKEN] [-i IDTAG] [-v VERBOSE] device [device...]
  -c CONFIG    Path to config file (default: /etc/default/checkdrives.cfg)
  -u URL       InfluxDB URL (overrides config)
  -t TOKEN     InfluxDB token (overrides config)
  -i IDTAG     Host/ID tag (overrides config)
  -v VERBOSE   0..2 verbosity (overrides config)
Devices may be written as "/dev/sda" or "/dev/sda,scsi"
EOF
}


# Parse flags first
while getopts ":c:u:t:i:v:hx" opt; do
  case "$opt" in
    c) CONFIG_FILE="$OPTARG"; ;;
    u) cli_INFURL="$OPTARG" ;;
    t) cli_TOKENSTRING="$OPTARG" ;;
    i) cli_IDTAG="$OPTARG" ;;
    v) cli_VERBOSE="$OPTARG" ;;
    x) cli_TESTING="1" ;;
    h) usage; exit 0 ;;
    \?) echo "Invalid option: -$OPTARG"; usage; exit 2 ;;
    :)  echo "Option -$OPTARG requires an argument"; usage; exit 2 ;;
  esac
done
shift $((OPTIND-1))

# Now source the chosen config ONCE
if [[ -r "$CONFIG_FILE" ]]; then
  # (Optional) clear any old values so the config defines them cleanly
  unset INFURL TOKENSTRING IDTAG VERBOSE DEVICES
  source "$CONFIG_FILE"
fi

# Apply defaults if still unset
: "${VERBOSE:=1}"
INFURL="${INFURL-}"
TOKENSTRING="${TOKENSTRING-}"
IDTAG="${IDTAG-}"
TESTING="${TESTING-}"

# Apply CLI overrides last (they always win if provided)
[[ -n "$cli_INFURL"     ]] && INFURL="$cli_INFURL"
[[ -n "$cli_TOKENSTRING" ]] && TOKENSTRING="$cli_TOKENSTRING"
[[ -n "$cli_IDTAG"      ]] && IDTAG="$cli_IDTAG"
[[ -n "$cli_VERBOSE"    ]] && VERBOSE="$cli_VERBOSE"
[[ -n "$cli_TESTING"    ]] && TESTING="$cli_TESTING"


DEVICES_ARG=()

# Devices from CLI or config
if (( $# > 0 )); then
  DEVICES_ARG=("$@")
fi


devices_to_process=()
if (( ${#DEVICES_ARG[@]} > 0 )); then
  devices_to_process=("${DEVICES_ARG[@]}")
elif [[ -n "${DEVICES[*]-}" ]]; then
  devices_to_process=("${DEVICES[@]}")
else
  echo "ERROR: No devices specified."
  usage; exit 2
fi

missing=()
[[ -z "${INFURL-}" ]] && missing+=("INFURL")
[[ -z "${TOKENSTRING-}" ]] && missing+=("TOKENSTRING")
[[ -z "${IDTAG-}" ]] && missing+=("IDTAG")
if (( ${#missing[@]} )); then
  echo "ERROR: Missing: ${missing[*]}"
  usage; exit 2
fi

(( VERBOSE >= 1 )) && {
  echo "CONFIG: $CONFIG_FILE "
  echo "URL: $INFURL"
  echo "TOKEN: $TOKENSTRING"
  echo "IDTAG: $IDTAG"
  echo "VERBOSE: $VERBOSE"
  echo "TESTING: $TESTING"
}

SUCCESSCNT=0

# --- your existing device loop here ---
for arg in "${devices_to_process[@]}"; do
  # The body of your current for-loop (smartctl, ROTA, fields, curl) goes here.
  (( VERBOSE >= 2 )) && echo "---- $arg ----"

  DEVICE="${arg%%,*}"         # device path (or name)
  DEVTYPE=""
  if [[ "$arg" == *","* ]]; then
    DEVTYPE="${arg#*,}"       # smartctl -d type
    (( VERBOSE >= 1 )) && echo "Non-standard type detected for $DEVICE: -d $DEVTYPE"
  else
    (( VERBOSE >= 1 )) && echo "Standard device: $DEVICE"
  fi

  # Normalize device path
  DEVNAME="${DEVICE##*/}"
  if [[ "$DEVICE" != /dev/* ]]; then
    DEVICE="/dev/$DEVNAME"
  fi

  # Collect smartctl data
  if [[ -n "$DEVTYPE" ]]; then
    data="$(sudo smartctl -a -d "$DEVTYPE" "$DEVICE" || true)"
    DEVICESTRING="$(echo "${DEVICE}_${DEVTYPE}" | tr ',' '_')"
  else
    data="$(sudo smartctl -a "$DEVICE" || true)"
    DEVICESTRING="$DEVICE"
  fi

  (( VERBOSE >= 2 )) && echo "DEV: $DEVICESTRING"
  (( VERBOSE >= 2 )) && echo "TYPE: ${DEVTYPE:-std}"

  # Check SMART support line
  smart_support="$(printf '%s\n' "$data" | grep -i 'SMART support' || true)"
  if [[ -n "$smart_support" ]]; then
    unsupported="$(printf '%s\n' "$smart_support" | grep -Ei 'Unavailable|Missing' || true)"
    if [[ -n "$unsupported" ]]; then
      echo "This device explicitly does NOT support SMART: $DEVICE"
      continue
    fi
  fi

  # Quick rotational heuristic via smartctl output (keep NVMe which lacks rpm)
  ff="$(printf '%s\n' "$data" | grep -F 'Form Factor' | grep -F 'inches' | awk -F':' '{print $2}' | sed 's/ \{2,\}/ /g' || true)"
  rr="$(printf '%s\n' "$data" | grep -F 'Rotation Rate' | awk -F':' '{print $2}' | sed 's/ \{2,\}/ /g' || true)"
  (( VERBOSE >= 2 )) && { echo "ff: $ff"; echo "rr: $rr"; }

  if [[ "$rr" == *"rpm"* ]]; then
    echo "$DEVICE appears to be a HDD (rpm present), skipping."
    continue
  fi

  # Extract fields (allow multiple vendors/labels)
  DevModel="$(printf '%s\n' "$data" \
    | grep -E 'Device Model:|Model Number:' \
    | awk -F':' '{print $2}' \
    | sed 's/ \{2,\}/ /g' \
    | head -n1 || true)"

  SerNum="$(printf '%s\n' "$data" \
    | grep -F 'Serial Number:' \
    | awk -F':' '{print $2}' \
    | sed 's/ \{2,\}/ /g' \
    | head -n1 || true)"

  FirmWare="$(printf '%s\n' "$data" \
    | grep -F 'Firmware Version:' \
    | awk -F':' '{print $2}' \
    | sed 's/ \{2,\}/ /g' \
    | head -n1 || true)"

  UserCapacity="$(printf '%s\n' "$data" \
    | grep -E 'User Capacity:|Total NVM Capacity|Size/Capacity:' \
    | awk -F':' '{print $2}' \
    | sed 's/ \{2,\}/ /g' \
    | awk '{print $1}' \
    | head -n1 \
    | uniq || true)"

  Power_on_Hours="$(printf '%s\n' "$data" \
    | grep -E 'Power_On_Hours|Power On Hours' \
    | awk '{print $NF}' \
    | sed 's/ \{2,\}/ /g' \
    | head -n1 || true)"

  [[ -z "$Power_on_Hours" ]] && Power_on_Hours="00"

  # Skip known unsupported platform
  if [[ "$DevModel" == *"_DELLBOSS_"* ]]; then
    echo "DELL BOSS does not support SMART; skipping."
    continue
  fi

  # Percent life remaining (drive-specific mapping)
  if [[ "$DevModel" == *"KINGSTON SEDC600M1920G"* ]]; then
#      echo "Kingston "
    RemainingPercent="$(printf '%s\n' "$data" | grep -E '231' | awk '{print $NF}' || true)"
  elif [[ "$DevModel" == *"INTEL SSDPEKNW010T8"* ]]; then
#      echo "Intel"
    RemainingPercent="$(printf '%s\n' "$data" | grep -F 'Available Spare:' | awk '{print $NF}' || true)"
  elif [[ "$DevModel" == *"Samsung SSD 980 PRO"* ]]; then
#      echo "Samsung"
    RemainingPercent="$(printf '%s\n' "$data" | grep -F 'Available Spare:' | awk '{print $NF}' || true)"
  elif [[ "$DevModel" == *"SSDSC2KG240G8R"* ]]; then
#      echo "SSD"
    RemainingPercent="$(printf '%s\n' "$data" | grep -F '245 Percent_Life_Remaining ' | awk '{print $NF}' || true)"
  elif [[ "$DevModel" == *"MTFDDAK480TDS"* ]]; then
#      echo "MTF"
    RemainingPercent="$(printf '%s\n' "$data" | grep -F '245 Percent_Life_Remaining ' | awk '{print $NF}' || true)"
  elif [[ "$DevModel" == *"WDC WDS100T2B0A"* ]]; then
#      echo "WDC"
    RemainingPercent="$(printf '%s\n' "$data" | grep -F '245 Percent_Life_Remaining ' | awk '{print $NF}' || true)"
  else
    echo "Unknown model, $DevModel"
    RemainingPercent="00"
  fi

#  echo "<---"
  # Normalize fields for line protocol
  DevModel_norm="$(printf '%s' "$DevModel" | sed 's/[[:space:]]\+/_/g')"
  UserCapacity_norm="$(printf '%s' "$UserCapacity" | sed 's/,//g')"
  FirmWare_norm="$(printf '%s' "$FirmWare" | sed 's/ //g')"
  SerNum_norm="$(printf '%s' "$SerNum" | sed 's/ //g')"
  Power_on_Hours_norm="$(printf '%s' "$Power_on_Hours" | sed 's/,//g')"
  RemainingPercent_norm="$(printf '%s' "$RemainingPercent" | sed 's/%//g')"
  [[ -z "$RemainingPercent_norm" ]] && RemainingPercent_norm="00"

  if [[ $VERBOSE -ge 1 ]]; then
    echo "$(date --rfc-3339='ns')"
    echo "$(hostname)"
    echo "$DEVICESTRING"
    echo "$DevModel_norm"
    echo "$SerNum_norm"
    echo "$FirmWare_norm"
    echo "$UserCapacity_norm"
    echo "$Power_on_Hours_norm"
    echo "$RemainingPercent_norm"
  fi

  if [[ -z "$DevModel_norm" ]]; then
    echo "Problems with $DEVICE (model empty) — check device type or permissions."
    echo "Does not report this device."
    continue
  fi

  HOSTNAME="$(hostname)"
  timestamp="$(date +%s)"

  if [[ $VERBOSE -ge 1 ]]; then
    echo "string="
    echo "storage,host=$IDTAG,Device=$DEVICESTRING,Model=$DevModel_norm,Serial=$SerNum_norm,Firmware=$FirmWare_norm,Capacity=$UserCapacity_norm PowerOn=$Power_on_Hours_norm,Remain=$RemainingPercent_norm $timestamp"
  fi


  http_code=""
  # Send to InfluxDB v2
  if [[ $TESTING == "1" ]]; then
      echo "TESTING; No http request sent. "
      echo "-->"
      echo "storage,host=$IDTAG,Device=$DEVICESTRING,Model=$DevModel_norm,Serial=$SerNum_norm,Firmware=$FirmWare_norm,Capacity=$UserCapacity_norm PowerOn=$Power_on_Hours_norm,Remain=$RemainingPercent_norm $timestamp"
  else
      response="$(
          curl -s -w "%{http_code}" --request POST \
      	  "$INFURL/api/v2/write?org=main-org&bucket=storage&precision=s" \
	  --header "Authorization: Token $TOKENSTRING" \
      	  --header "Content-Type: text/plain; charset=utf-8" \
      	  --header "Accept: application/json" \
      	  --data-binary "storage,host=$IDTAG,Device=$DEVICESTRING,Model=$DevModel_norm,Serial=$SerNum_norm,Firmware=$FirmWare_norm,Capacity=$UserCapacity_norm PowerOn=$Power_on_Hours_norm,Remain=$RemainingPercent_norm $timestamp"
  	  )" || true

  http_code="$(tail -n1 <<< "$response")"
  fi
  
  (( VERBOSE >= 1 )) && echo "hc=$http_code"

  if [[ -z "$http_code" ]]; then
    echo "Curl returned no HTTP code; response: $response"
    exit 1
  fi

  if [[ ! "$http_code" =~ ^2[0-9]{2}$ ]]; then
    echo "Request failed: HTTP $http_code; response: $response"
    exit 1
  fi

  ((SUCCESSCNT++))
done

if [[ $VERBOSE -ge 1 ]]; then
  echo "Successfully sent $SUCCESSCNT devices."
fi
