#!/usr/bin/env bash

# http://stackoverflow.com/a/28776100
if [[ $(id -u) != 0 ]]; then
	echo 'Please run as ROOT.';
	exit;
fi

reset

# https://serverfault.com/questions/534627/what-does-the-sync-command-do/534633
# https://unix.stackexchange.com/questions/87908/how-do-you-empty-the-buffers-and-cache-on-a-linux-system
free --human --mega --wide
sync && sleep 0
# echo 3 > /proc/sys/vm/drop_caches && sleep 1
sysctl vm.drop_caches=3 && sleep 0
sync && sleep 0
free --human --mega --wide
