
# 20201207041850,20210206223234

device_name='AT Translated Set 2 keyboard'
device_prop='Device Enabled'
device_state=$(xinput list-props "${device_name}" | grep "${device_prop}" | grep -o "[01]$")

toggle_1() {
	if [[ $device_state == 0 ]]; then
		xinput enable "${device_name}"
	fi
}
toggle_0() {
	if [[ $device_state == 1 ]]; then
		xinput disable "${device_name}"
	fi
}

status() {
	if [[ $device_state == 1 ]]; then echo "Currently \"${device_name}\" is ON"; fi
	if [[ $device_state == 0 ]]; then echo "Currently \"${device_name}\" is OFF"; fi
}
usage() {
	status
	echo "	-1	Turn ON"
	echo "	-0	Turn OFF"
	echo "	-n	override \${device_name} (todo next)"
	echo "	-p	override \${device_prop} (todo next)"
	echo "	-s	state/status"
	exit 1
}

while getopts ':01s' i; do case "${i}" in
	(0) toggle_0 ;;
	(1) toggle_1 ;;
	(s) status ;;
	(*) usage ;;
esac done

if [[ "$#" == 0 ]]; then usage; fi

exit 0
