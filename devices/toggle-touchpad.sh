#!/bin/bash
<< comments___
toggle touchpad (laptop shortcut fix) ubuntu/debian

open your desktop-enviroment settings, goto keyboard section,
create new shortcut. choose whatever combination you like.

author 	github/v-dimitrov
author 	github/anovsiradj
version	20140910,20180903
origin 	https://gist.github.com/v-dimitrov/8814153
comments___

devicePropertyName='Device Enabled'
deviceName=` xinput list --name-only | grep --ignore-case 'touchpad' ` # find touchpad device #
deviceIsOn=` xinput list-props "$deviceName" | grep "$devicePropertyName" | tail --bytes=2 ` # find device status #

icon='dialog-information'
icon0='touchpad-disabled-symbolic'
icon1='input-touchpad-symbolic'

case "$deviceIsOn" in
	0)
		notify-send --icon="$icon1,$icon" "$deviceName [ON]" "Your Touchpad is now Enabled"
		xinput set-prop "$deviceName" "$devicePropertyName" 1
		;;
	1)
		notify-send --icon="$icon0,$icon" "$deviceName [OFF]" "Your Touchpad is now Disabled"
		xinput set-prop "$deviceName" "$devicePropertyName" 0
		;;
	*)
		notify-send --icon="$icon" --expire-time=10000 "$deviceName [ERROR]" "'$devicePropertyName': '$deviceIsOn';"
		;;
esac
