#!/usr/bin/env bash

# https://askubuntu.com/a/400430/613129
# https://wiki.winehq.org/FAQ#How_do_I_clean_the_Open_With_List.3F
# https://www.google.com/search?q=wine%20disable%20file%20associations

my_version=2019.08.03-1

my_name='WINE Vacuum Cleaner' # / WVC / WINEVC
my_author='mayendra costanov (anovsiradj) <anov.siradj22@gmail.com>'

my_run=0
my_help=0
my_debug=0
my_verbose=0

# mengaktifkan null untuk glob
# https://unix.stackexchange.com/a/293650/350578
shopt -s nullglob

# https://stackoverflow.com/a/6482403/3036312
if [ $# == 0 ]; then
	# https://stackoverflow.com/a/30078353/3036312
	# echo 'empty arguments, use --k or --k=v (run,verbose).' 1>&2; exit 1;
	my_run=0
	my_help=0
fi
# exit

my_regex_1_keyvalue='^--(\w+)=(.+)$'
my_regex_2_toggle='^--(\w+)$'
# https://stackoverflow.com/a/14203146/3036312
for my_arg in $@; do
	if [ 0 == 1 ]; then exit;
	elif [ $my_arg == '-h' ] || [ $my_arg == '--help' ]; then my_help=1; my_run=0; my_verbose=1;
	elif [ $my_arg == '-v' ] || [ $my_arg == '--version' ]; then echo $my_version; exit;
	elif [ $my_arg == '-1' ] || [ $my_arg == '--1' ]; then my_run=1;
	# https://unix.stackexchange.com/a/196534/350578
	# https://gist.github.com/JPvRiel/4cf82d42beb6387dec7eadc43cef6c17
	elif [[ $my_arg =~ $my_regex_1_keyvalue ]]; then
		# https://stackoverflow.com/a/37266859/3036312
		my_k=${BASH_REMATCH[1]}
		my_k="my_${my_k}"
		my_v=${BASH_REMATCH[2]}

		# https://stackoverflow.com/a/26558826/3036312
		declare "${my_k}"="${my_v}";
	elif [[ $my_arg =~ $my_regex_2_toggle ]]; then
		my_k=${BASH_REMATCH[1]}
		my_k="my_${my_k}"
		my_v="${!my_k}"
		if [ $my_debug == 1 ]; then echo $my_k=$my_v; fi

		# https://ubuntuforums.org/showthread.php?t=2142639&p=12636894#post12636894
		my_v=$((1-my_v))
		if [ $my_debug == 1 ]; then echo $my_k=$my_v; fi

		if [ $my_k == 'my_debug' ]; then my_verbose=$my_v; fi
		# https://stackoverflow.com/a/26558826/3036312
		declare "${my_k}"="${my_v}";
	else
		# https://stackoverflow.com/a/30078353/3036312
		echo "unknown \"${my_arg}\" argument" $'\n' 1>&2;
		exit 1;
	fi
done
# exit

if [ $my_help == 1 ]; then my_run=0; my_verbose=1; fi
if [ $my_debug == 1 ]; then my_verbose=1; fi
if [ $my_verbose == 1 ]; then
	# https://stackoverflow.com/a/13192701/3036312
	echo "${my_name} (${my_version}) ${my_author}" $'\n';
fi

if [ $my_help == 1 ]; then
	echo '-1 | --1| --run[=0|1]';
	echo '-h | --help[=0|1] ';
	echo '--verbose[=0|1]';
	echo '-v | --version';
	echo $'\n';
fi

# https://stackoverflow.com/a/8920266/3036312
# if [ $my_verbose == 1 ] && [ $my_run == 1 ]; then echo "rm ${my_files}"; fi

my_files=~/.local/share/applications/wine-extension-*.desktop
for my_file in $my_files; do if [ $my_run == 1 ]; then rm $my_file; elif [ $my_verbose == 1 ]; then echo '#1' $my_file; fi; done
my_files=~/.local/share/icons/hicolor/*/*/application-x-wine-extension-*.png
for my_file in $my_files; do if [ $my_run == 1 ]; then rm $my_file; elif [ $my_verbose == 1 ]; then echo '#2' $my_file; fi; done
my_files=~/.local/share/mime/*/x-wine-extension-*.xml
for my_file in $my_files; do if [ $my_run == 1 ]; then rm $my_file; elif [ $my_verbose == 1 ]; then echo '#3' $my_file; fi; done

# https://wiki.archlinux.org/index.php/XDG_MIME_Applications
my_path=~/.local/share/mime
if [ $my_run == 1 ]; then update-mime-database $my_path; elif [ $my_verbose == 1 ]; then echo '#4' $my_path $'\n'; fi

my_path=~/.local/share/applications
if [ $my_run == 1 ]; then update-desktop-database $my_path; elif [ $my_verbose == 1 ]; then echo '#5' $my_path $'\n'; fi

# https://askubuntu.com/q/722708/613129
my_cmd=gtk-update-icon-cache
if [ $my_run == 1 ]; then
	# http://mywiki.wooledge.org/BashFAQ/050
	# https://stackoverflow.com/a/32279944/3036312
	$my_cmd;
elif [ $my_verbose == 1 ]; then echo '#6' $my_cmd $'\n'; fi

# https://stackoverflow.com/q/52738912/3036312
# my_file=~/.local/share/mime/globs
# while read my_line; do echo "${my_line}"; done < $my_file
# my_file=~/.local/share/mime/globs2
# while read my_line; do echo "${my_line}"; done < $my_file

if [ $my_run == 0 ] && [ $my_help == 0 ]; then
	# https://stackoverflow.com/a/30078353/3036312
	echo $'use "--run" or "--run=1" argument to execute.\n' 1>&2;
	exit 1;
fi
