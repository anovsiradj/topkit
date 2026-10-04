#!/bin/bash
<< comments___
toggle touchpad (laptop shortcut fix) ubuntu/debian

open your desktop-enviroment settings, goto keyboard section,
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
# find touchpad device #
deviceName=$(xinput list --name-only | grep --ignore-case 'touchpad')
if [[ -z "$deviceName" ]]; then
	notify-send --icon="$icon" "ERROR" "Touchpad Not Found"
	exit 1
fi

# find device status #
# not found will trigger "unable to find device"
deviceStatus=$(xinput list-props "$deviceName" | grep "$devicePropertyName" | tail --bytes=2)

# echo "devicePropertyName : [$devicePropertyName]"
# echo "deviceName         : [$deviceName]"
# echo "deviceStatus       : [$deviceStatus]"
# exit

if [[ -z "$deviceStatus" ]]; then
	notify-send --icon="$icon" "ERROR" "Touchpad Status Unknown"
	exit 1
fi

case "$deviceStatus" in
	0)
		notify-send --icon="$icon1,$icon" "$deviceName [ON]" "Your Touchpad is now Enabled"
		xinput set-prop "$deviceName" "$devicePropertyName" 1
		;;
	1)
		notify-send --icon="$icon0,$icon" "$deviceName [OFF]" "Your Touchpad is now Disabled"
		xinput set-prop "$deviceName" "$devicePropertyName" 0
		;;
	*)
		notify-send --icon="$icon" --expire-time=10000 "$deviceName [ERROR]" "'$devicePropertyName': '$deviceStatus';"
		;;
esac
