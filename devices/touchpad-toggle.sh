#!/bin/bash
<< comments___
toggle touchpad (laptop shortcut fix) ubuntu/debian

open your desktop-environment settings, goto keyboard section,
create new shortcut. choose whatever combination you like.

author 	github/anovsiradj
version	20140910,20180903,20260731,20261005
origin 	https://gist.github.com/v-dimitrov/8814153
comments___

# set -e

icon='dialog-information'
icon0='touchpad-disabled-symbolic'
icon1='input-touchpad-symbolic'

devicePropertyName='Device Enabled'
scriptDir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
cacheFile="$scriptDir/touchpad-toggle.sh.tmp"

# ------------------------------------------------------------------
usage() {
	cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Toggle or explicitly enable/disable every xinput pointer device whose
name matches the cached name. Cache is stored in $cacheFile.

Before using as a keyboard shortcut, set the cached device name once:

    $(basename "$0") -d "SYNA30D2:00 06CB:CE08"

Use \`$(basename "$0") -l\` to inspect names via \`xinput list\`.

Default behaviour (no mode flag):
  Determine the status of the FIRST matching device. If it is enabled
  (1) then disable ALL matching devices. If it is disabled (0) then
  enable ALL matching devices.

Options:
  -l, --list            Print raw \`xinput list\` to stdout
  -d, --device <name>   Cache the given xinput device name (value only)
  -c, --clear-cache     Remove the cached device selection
      --on              Enable every matched device (no toggle)
      --off             Disable every matched device (no toggle)
  -h, --help            Show this help

EOF
}

# ------------------------------------------------------------------
# Numeric xinput ids of slave/floating pointer devices only.
get_pointer_ids() {
	xinput list \
	| grep -E '(\[slave\s+pointer|\[floating slave\])' \
	| grep -oE 'id=[0-9]+' \
	| cut -d= -f2
}

# ------------------------------------------------------------------
list_devices() {
	xinput list
}

# ------------------------------------------------------------------
# Resolve a cached device NAME into a SPACE-SEPARATED LIST of numeric
# xinput ids. Every pointer whose xinput name equals the cached
# name (exact match) is included, preserving the order returned by
# get_pointer_ids. Multiple matches are intentional: they will ALL be
# toggled together. Prints nothing (empty) when nothing matches.
resolve_name_to_ids() {
	local wantedName="$1"
	local allIds id name matches=""
	allIds=$(get_pointer_ids)
	for id in $allIds; do
		name=$(xinput list --name-only "$id" 2>/dev/null) || continue
		[[ "$name" == "$wantedName" ]] && matches="$matches $id"
	done
	echo "${matches# }"
}

# ------------------------------------------------------------------
# Read the 0/1 Device Enabled status of a single xinput id. Empty on
# any failure so the caller can bail out.
get_device_status() {
	local id="$1"
	xinput list-props "$id" 2>/dev/null \
	| grep -E "^\s*${devicePropertyName}\s*\([0-9]+\):" \
	| awk -F':[[:space:]]*' '{print $2}' \
	| tr -d '[:space:]'
}

# ------------------------------------------------------------------
cache_set() {
	local deviceName="$1"
	printf '%s' "$deviceName" > "$cacheFile"
}

cache_get() {
	[[ -f "$cacheFile" ]] || return 1
	local value
	value=$(< "$cacheFile")
	[[ -n "$value" ]] || return 1
	echo "$value"
}

cache_clear() {
	if [[ -f "$cacheFile" ]]; then
		rm -f "$cacheFile"
		echo "Cache removed: $cacheFile"
	else
		echo "No cache file at $cacheFile"
	fi
}

# ------------------------------------------------------------------
# Args parsing
action=""
mode="toggle"   # toggle | on | off
cliDeviceName=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		-l|--list)        action="list"; shift ;;
		-d|--device)
			if [[ -z "${2:-}" ]]; then
				echo "ERROR: option '--device / -d' requires an xinput device name" >&2
				usage >&2
				exit 2
			fi
			action="device"
			cliDeviceName="$2"
			shift 2
			;;
		-c|--clear-cache) action="clear"; shift ;;
		--on)             mode="on"; shift ;;
		--off)            mode="off"; shift ;;
		-h|--help)        usage; exit 0 ;;
		--) shift; break ;;
		-*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
		*) shift ;;
	esac
done

case "$action" in
	list)
		list_devices
		exit 0
		;;
	clear)
		cache_clear
		exit 0
		;;
	device)
		# User explicitly asked to cache a name. We accept it as-is, but
		# still verify that at least one current device matches it so
		# typos are caught early.
		matches=$(resolve_name_to_ids "$cliDeviceName")
		if [[ -z "$matches" ]]; then
			echo "ERROR: no current xinput pointer named '$cliDeviceName'" >&2
			echo "       Use \`$(basename "$0") -l\` to see valid names." >&2
			notify-send --icon="$icon" "ERROR" "No pointer named '$cliDeviceName'"
			exit 1
		fi
		cache_set "$cliDeviceName"
		count=0; for _ in $matches; do count=$((count+1)); done
		echo "Cached: '$cliDeviceName' ($count device(s): $matches)"
		exit 0
		;;
esac

# ------------------------------------------------------------------
# Resolve cached name -> list of matching ids.
cachedName=""
if ! cachedName=$(cache_get 2>/dev/null); then
	notify-send --icon="$icon" "ERROR" \
		"No cached touchpad. Set it first: $(basename "$0") -d \"<device name>\""
	exit 1
fi

deviceIds=$(resolve_name_to_ids "$cachedName")
if [[ -z "$deviceIds" ]]; then
	notify-send --icon="$icon" "ERROR" \
		"Cached touchpad '$cachedName' not found. Use -l to list and -d to set."
	exit 1
fi

# --- decide target value ------------------------------------------
firstId="${deviceIds%% *}"
firstStatus=$(get_device_status "$firstId")
if [[ -z "$firstStatus" ]]; then
	notify-send --icon="$icon" "ERROR" "Touchpad Status Unknown ($cachedName, id=$firstId)"
	exit 1
fi

targetValue=""
case "$mode" in
	on)     targetValue=1 ;;
	off)    targetValue=0 ;;
	toggle)
		case "$firstStatus" in
			0) targetValue=1 ;;
			1) targetValue=0 ;;
			*)
				notify-send --icon="$icon" --expire-time=10000 \
					"$cachedName [ERROR]" "'$devicePropertyName': '$firstStatus';"
				exit 1
				;;
		esac
		;;
esac

# --- apply target value to EVERY matched id -----------------------
labelOn="ON"
labelOff="OFF"
msgOn="Your Touchpad is now Enabled"
msgOff="Your Touchpad is now Disabled"
iconActive="$icon1"

if [[ "$targetValue" == "0" ]]; then
	labelActive="$labelOff"
	msgActive="$msgOff"
	labelFail="Failed to disable Touchpad"
	iconActive="$icon0"
else
	labelActive="$labelOn"
	msgActive="$msgOn"
	labelFail="Failed to enable Touchpad"
fi

failed=""
count=0
for id in $deviceIds; do
	count=$((count+1))
	xinput set-prop "$id" "$devicePropertyName" "$targetValue" 2>/dev/null || failed="$failed $id"
done

if [[ -n "$failed" ]]; then
	notify-send --icon="$icon" "ERROR" "${labelFail} (failed:${failed})"
	exit 1
fi

countLabel=""
(( count > 1 )) && countLabel=" ($count devices)"
notify-send --icon="$iconActive,$icon" "$cachedName [$labelActive]$countLabel" "$msgActive"
