#!/usr/bin/env bash
set -euo pipefail

# Usage: ./buildConfig.sh [models_file]
# Default models file: ./models
# Set DEBUG=1 in environment to enable debug output, e.g. DEBUG=1 ./buildConfig.sh

models_file="${1:-./models}"
debug=${DEBUG:-0}

log_debug() {
    if [[ "$debug" -ne 0 ]]; then
        printf 'DEBUG: %s\n' "$*" >&2
    fi
}

# --- read block devices (only TYPE="disk" and ROTA="0") ---
log_debug "Gathering block devices with lsblk (TYPE=disk, ROTA=0)..."
lsblk_data="$(lsblk -dn -o NAME,MODEL,TYPE,ROTA -P | grep 'TYPE=\"disk\"' | grep 'ROTA=\"0\"' || true)"
if [[ -z "$lsblk_data" ]]; then
    echo "No non-rotational disk devices found (ROTA=0)." >&2
fi
log_debug "Raw lsblk data:"
while IFS= read -r L; do log_debug "  $L"; done <<< "$lsblk_data"

# --- parse devices into array of "NAME|MODEL" ---
devices=()
while IFS= read -r line; do
    # Extract NAME and MODEL from KEY="VALUE" pairs
    NAME="$(printf '%s\n' "$line" | sed -n 's/.*NAME="\([^"]*\)".*/\1/p')"
    MODEL="$(printf '%s\n' "$line" | sed -n 's/.*MODEL="\([^"]*\)".*/\1/p' || true)"
    # MODEL can be empty; keep it as empty string but preserve both fields
    devices+=( "${NAME}|${MODEL}" )
    log_debug "Parsed device: NAME='${NAME}' MODEL='${MODEL}'"
done <<< "$lsblk_data"

# --- read models file ---
if [[ ! -f "$models_file" ]]; then
    echo "Models file not found: $models_file" >&2
    exit 2
fi

models=()
while IFS= read -r m || [[ -n "$m" ]]; do
    # Trim whitespace
    m_trimmed="$(printf '%s' "$m" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    # Skip blank lines and comments
    if [[ -z "$m_trimmed" ]] || [[ "$m_trimmed" == \#* ]]; then
        continue
    fi
    models+=( "$m_trimmed" )
done < "$models_file"

log_debug "Loaded models (count=${#models[@]}):"
for m in "${models[@]}"; do log_debug "  [$m]"; done

# --- matching ---
# We'll track:
#  - matched_by_model: associative array counting matches per model
#  - matches_list: lines "model|NAME|/dev/NAME|device_model"
#  - device_matched: whether each device had at least one match
declare -A matched_by_model
matches_list=()
device_unmatched_list=()

for dev in "${devices[@]}"; do
    NAME="${dev%%|*}"
    MODEL="${dev#*|}"        # may be empty string
    dev_display="${MODEL}"
    if [[ -z "$dev_display" ]]; then
        dev_display="${NAME}"
    fi

    log_debug "Evaluating device /dev/${NAME} with model display '${dev_display}'"

    matched_any=0
    for model in "${models[@]}"; do
        # case-insensitive substring test: is model contained in device MODEL?
        # both lowercased
        # If device MODEL is empty, we will NOT match (unless model equals NAME)
        model_lc="$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')"
        dev_model_lc="$(printf '%s' "$MODEL" | tr '[:upper:]' '[:lower:]')"

        if [[ -n "$dev_model_lc" && "$dev_model_lc" == *"$model_lc"* ]]; then
            # matched
            matched_any=1
            matched_by_model["$model"]=$(( ${matched_by_model["$model"]:-0} + 1 ))
            # save a structured entry: model|NAME|/dev/NAME|device_MODEL (device_MODEL may be blank)
            matches_list+=( "$model|$NAME|/dev/$NAME|$MODEL" )
            log_debug "Device /dev/${NAME} MATCHES model '$model' (device MODEL='$MODEL')"
            # do NOT break: allow multiple models matching same device in case of overlaps
        else
            log_debug "Device /dev/${NAME} does NOT match model '$model' (test: device '${dev_model_lc}' contains '${model_lc}')"
        fi
    done

    if [[ "$matched_any" -eq 0 ]]; then
        # device not matched by any model
        device_unmatched_list+=( "$dev_display|$NAME" )
        log_debug "Device /dev/${NAME} had NO matches (recorded as unmatched)."
    fi
done

# --- models not found on any device ---
models_not_found=()
for model in "${models[@]}"; do
    if [[ -z "${matched_by_model["$model"]:-}" ]]; then
        models_not_found+=( "$model" )
    fi
done

# --- Output the report ---
echo
echo "======================================"
echo " MATCH REPORT"
echo "======================================"
echo

# Matched list header
echo "Matched"
echo "-------"
if [[ ${#matches_list[@]} -eq 0 ]]; then
    echo "  (none)"
else
    # Print unique matched entries grouped by model; but user asked "model and device name printed" for matched
    # We'll print each match line: "<Model> /dev/<NAME>"
    # If the model in matches entry is empty (shouldn't happen because models come from file), we skip printing empty.
    # Keep order: as discovered.
    for entry in "${matches_list[@]}"; do
        IFS='|' read -r m name devpath devmodel <<< "$entry"
        # For matched we print: "<m> <devpath>" and optionally show device model in parentheses if different
        if [[ -n "$devmodel" ]]; then
            printf '  %s %s\n' "$m" "$devpath"
        else
            # no device MODEL, print the NAME instead
            printf '  %s %s\n' "$m" "$devpath"
        fi
    done
fi
echo

# Unmatched list header
echo "Unmatched"
echo "---------"
if [[ ${#device_unmatched_list[@]} -eq 0 ]]; then
    echo "  (none)"
else
    # Print each unmatched device as: "<device_MODEL_or_NAME> /dev/<NAME>"
    for entry in "${device_unmatched_list[@]}"; do
        IFS='|' read -r dev_display name <<< "$entry"
        printf '  %s /dev/%s\n' "$dev_display" "$name"
    done
fi
echo


# # Models not found
# echo "Models NOT found on any device:"
# if [[ ${#models_not_found[@]} -eq 0 ]]; then
#     echo "  (all models were found on at least one device)"
# else
#     for m in "${models_not_found[@]}"; do
#         printf '  - %s\n' "$m"
#     done
# fi
# echo

# # Print the regex used for each model (for debugging / transparency)
# echo "Model -> Regex used (case-insensitive substring test):"
# for m in "${models[@]}"; do
#     # Create a displayed regex: replace spaces with .*
#     disp_regex=".*${m// /.*}.*"
#     echo "  '$m' -> '$disp_regex'  (case-insensitive substring match)"
# done

echo
echo "Devices scanned: ${#devices[@]}"
echo "Matches found: ${#matches_list[@]}"
echo "Done."
