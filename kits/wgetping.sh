#!/usr/bin/env bash

# todos: curlping; notify on error;

declare -a urls=()

for i in $@; do
	if [[ $i == http* ]]; then
		urls+=($i)
	fi
done

for url in "${urls[@]}"; do
	wget \
	--quiet \
	--spider \
	--tries=3 \
	--server-response \
	--content-on-error \
	$url
done

exit 0
