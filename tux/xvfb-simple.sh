
# @author: anovsiradj;
# @version: 20191213184130;
# @reference
# https://linux.die.net/man/1/xvfb
# https://askubuntu.com/a/432257

xvfb_prefix=Xvfb

screen=0
display=${DISPLAY}
wxhxd=128x96x8

run=0
list=0
kill=0

help=0
function help_comments() {
	echo 'Simple Xvfb (Display)'
	echo
	echo 'Examples:'
	echo "$(basename $0) :69"
	echo "$(basename $0) --display=:69"
	echo "$(basename $0) --display=:69 --screen=${screen}"
	echo "$(basename $0) --display=:69 --screen=${screen} --wxhxd=${wxhxd}"
	echo
	echo 'Arguments:'
	echo '?|--display=?'
	echo '--screen=?'
	echo '--wxhxd=? (WIDTH ✕ HEIGHT ✕ DEPTH)'
	echo '-l|--list[=0|1] (shortcut "ps")'
	echo '-h|--help[=0|1]'
	echo
	echo '--kill=PID (shortcut "kill")'
	echo "--xvfb_prefix=${xvfb_prefix}"
}

if [ $# == 0 ]; then
	echo 'empty arguments, use --k (toggle 0/1) or --k=v (assignment). use -h|--help[=1] for help.' 1>&2
	exit 1
fi

args_regexp_display='^\:[0-9]+$'
args_regexp_keyvalue='^--(\w+)=(.+)$'
args_regexp_toggle='^--(\w+)$'
for arg in $@; do
	if [ 0 == 1 ]; then exit;
	elif [[ $arg =~ $args_regexp_display ]]; then
		display="${arg}"
		run=1
	elif [[ $arg =~ $args_regexp_toggle ]]; then
		k=${BASH_REMATCH[1]}
		v="${!k}"
		v=$((1-v))
		declare "${k}"="${v}"
	elif [[ $arg =~ $args_regexp_keyvalue ]]; then
		k=${BASH_REMATCH[1]}
		v=${BASH_REMATCH[2]}
		declare "${k}"="${v}"
	elif [ $arg == '-h' ]; then help=1;
	elif [ $arg == '-l' ]; then list=1;
	else
		echo "unknown \"${arg}\" argument" $'\n' 1>&2
		exit 1
	fi
done

# if [ $help == 1 ] || [ $version == 1 ]; then echo "@version: ${version_array[${#version_array[@]}-1]};"; fi
if [[ $help == 1 ]]; then
	help_comments
	exit 0
fi

if [[ $list == 1 ]]; then
	ps -ef | grep '[X]vfb'
	exit 0
fi

if [[ $kill != 0 ]]; then
	kill -SIGINT "${kill}"
	exit 0
fi

if [[ $run == 1 ]] && [[ $display != ':0' ]]; then
	is=$(xdpyinfo -display "${display}" >/dev/null 2>&1 && echo 1 || echo 0)

	if [[ $is == 0 ]]; then
		$xvfb_prefix "${display}" -screen "${screen}" "${wxhxd}" &
	fi

	exit 0
fi
