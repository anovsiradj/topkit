#!/usr/bin/env bash
# Launches scrcpy inside a window-manager-managed GTK3 X11 viewport.
#
# The wrapper owns the viewport and moves the scrcpy X11 window inside it.
# Closing either process terminates the other, so the viewport cannot remain
# orphaned on the screen.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOURCE="$SCRIPT_DIR/gtk-scrcpy-wrapper.c"
BUILD_DIR="$PROJECT_DIR/tmp"
WRAPPER="$BUILD_DIR/gtk-scrcpy-wrapper"
SCRCPY_BIN="${SCRCPY_BIN:-scrcpy}"

WRAPPER_WIDTH="${SCRCPY_SCROLL_WIDTH:-720}"
WRAPPER_HEIGHT="${SCRCPY_SCROLL_HEIGHT:-600}"
SCROLL_STEP="${SCRCPY_SCROLL_STEP:-50}"
CHILD_HEIGHT="${SCRCPY_SCROLL_CHILD_HEIGHT:-1920}"
MAX_SIZE="${SCRCPY_SCROLL_MAX_SIZE:-1920}"
# Keep this in sync with SCRCPY_EXIT_REPORT_STATUS in gtk-scrcpy-wrapper.c.
WRAPPER_SCRCPY_EXIT_STATUS=125

fail() {
	echo "$*" >&2
	exit 2
}

if (( BASH_VERSINFO[0] < 5
		|| (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 1) )); then
	fail "Bash 5.1 or newer is required"
fi

require_command() {
	command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

option_matches() {
	local candidate="$1"
	local canonical="$2"

	[[ "$candidate" == "$canonical" || "$canonical" == "$candidate"* ]]
}

validate_scrcpy_args() {
	local argument
	local canonical
	local char
	local index
	local name
	local next_argument
	local next_index
	local short_index
	local short_name
	local total
	local value
	local -a conflicting_options=(
		--always-on-top
		--fullscreen
		--flex-display
		--help
		--list-apps
		--list-camera-sizes
		--list-cameras
		--list-displays
		--list-encoders
		--max-fps
		--max-size
		--new-display
		--no-playback
		--no-video
		--no-video-playback
		--no-window
		--otg
		--render-fit
		--v4l2-sink
		--version
		--window-height
		--window-title
		--window-width
	)

	total=$#
	for ((index = 1; index <= total; index++)); do
		argument="${!index}"
		case "$argument" in
		--)
			fail "The scrcpy option terminator is not supported by the scroll wrapper"
			;;
		--*=*)
			name="${argument%%=*}"
			value="${argument#*=}"
			;;
		--*)
			name="$argument"
			value=""
			;;
		-?*)
			name="${argument%%=*}"
			short_name="${name#-}"
			for ((short_index = 0; short_index < ${#short_name}; short_index++)); do
				char="${short_name:short_index:1}"
				case "$char" in
				f|h|m|N|v|x)
					fail "Unsupported scrcpy option for the scroll wrapper: $argument"
					;;
				b|p|r|s|V)
					# The rest of this cluster is the option value.
					break
					;;
				d|e|G|K|M|n|S|t|w)
					;;
				*)
					# Unknown options are left for scrcpy to validate.
					break
					;;
				esac
			done
			continue
			;;
		*)
			continue
			;;
		esac

		for canonical in "${conflicting_options[@]}"; do
			if option_matches "$name" "$canonical"; then
				fail "Unsupported or conflicting scrcpy option for the scroll wrapper: $argument"
			fi
		done

		if [[ "$name" == --list-* ]]; then
			fail "Unsupported scrcpy option for the scroll wrapper: $argument"
		fi

		if option_matches "$name" "--mouse"; then
			if [[ "$value" == "disabled" ]]; then
				fail "Unsupported scrcpy option for the scroll wrapper: $argument"
			fi
			if [[ -z "$value" && $((index + 1)) -le total ]]; then
				next_index=$((index + 1))
				next_argument="${!next_index}"
				if [[ "$next_argument" == "disabled" ]]; then
					fail "Unsupported scrcpy option for the scroll wrapper: $argument disabled"
				fi
			fi
		fi
	done
}

normalize_decimal() {
	local value="$1"

	while [[ "$value" == 0* && ${#value} -gt 1 ]]; do
		value="${value#0}"
	done

	printf '%s\n' "$value"
}

validate_positive_integer() {
	local name="$1"
	local value="$2"
	local normalized

	[[ "$value" =~ ^[0-9]+$ ]] || fail "Invalid $name: $value"
	normalized="$(normalize_decimal "$value")"
	[[ "$normalized" != "0" ]] || fail "Invalid $name: $value"
}

validate_integer_range() {
	local name="$1"
	local value="$2"
	local minimum="$3"
	local maximum="$4"
	local normalized
	local LC_ALL=C

	[[ "$value" =~ ^[0-9]+$ ]] || fail "Invalid $name: $value"
	normalized="$(normalize_decimal "$value")"

	if (( ${#normalized} > ${#maximum} )); then
		fail "Invalid $name: $value (maximum $maximum)"
	fi
	if (( 10#$normalized > 10#$maximum )); then
		fail "Invalid $name: $value (maximum $maximum)"
	fi

	if (( ${#normalized} < ${#minimum} )); then
		fail "Invalid $name: $value (minimum $minimum)"
	fi
	if (( 10#$normalized < 10#$minimum )); then
		fail "Invalid $name: $value (minimum $minimum)"
	fi
}

require_command "$SCRCPY_BIN"
require_command xdotool
require_command xprop
require_command xwininfo
require_command pkg-config
require_command "${CC:-cc}"
pkg-config --exists gtk+-3.0 || fail "GTK3 development package not found: gtk+-3.0"

validate_scrcpy_args "$@"
validate_integer_range SCRCPY_SCROLL_WIDTH "$WRAPPER_WIDTH" 320 16384
validate_integer_range SCRCPY_SCROLL_HEIGHT "$WRAPPER_HEIGHT" 320 16384
validate_integer_range SCRCPY_SCROLL_STEP "$SCROLL_STEP" 1 1000
validate_positive_integer SCRCPY_SCROLL_CHILD_HEIGHT "$CHILD_HEIGHT"
validate_positive_integer SCRCPY_SCROLL_MAX_SIZE "$MAX_SIZE"

if [[ ! -x "$WRAPPER" || "$SOURCE" -nt "$WRAPPER" ]]; then
	BUILD_TMP_DIR=""
	BUILD_TMP=""
	cleanup_build() {
		if [[ -n "${BUILD_TMP:-}" ]]; then
			rm -f -- "$BUILD_TMP"
		fi
		if [[ -n "${BUILD_TMP_DIR:-}" ]]; then
			rmdir -- "$BUILD_TMP_DIR" 2>/dev/null || true
		fi
	}

	mkdir -p "$BUILD_DIR" || exit 1
	BUILD_TMP_DIR="$(mktemp -d "$BUILD_DIR/gtk-scrcpy-wrapper-build.XXXXXX")" || exit 1
	BUILD_TMP="$BUILD_TMP_DIR/gtk-scrcpy-wrapper"
	trap cleanup_build EXIT
	if ! "${CC:-cc}" -std=c11 -O2 -Wall -Wextra -Wpedantic \
			-o "$BUILD_TMP" "$SOURCE" \
			$(pkg-config --cflags --libs gtk+-3.0) -lX11 -lXi; then
		exit 1
	fi
	chmod 755 "$BUILD_TMP" || exit 1
	mv -f -- "$BUILD_TMP" "$WRAPPER" || exit 1
	BUILD_TMP=""
	rmdir -- "$BUILD_TMP_DIR" || exit 1
	BUILD_TMP_DIR=""
	trap - EXIT
fi

SCRPYPID=""
SCRPYP_START_TIME=""
WRAPPER_PID=""
WRAPPER_START_TIME=""
WATCHDOG_PID=""
WATCHDOG_START_TIME=""
FIRST_PID=""
FIRST_STATUS=0
FIRST_WAS_SCRPYPY=0

process_is_running() {
	local pid="$1"
	local stat_line
	local state

	[[ -n "$pid" && -r "/proc/$pid/stat" ]] || return 1
	IFS= read -r stat_line 2>/dev/null < "/proc/$pid/stat" || return 1
	state="${stat_line##*) }"
	state="${state%% *}"
	[[ -n "$state" && "$state" != "Z" && "$state" != "X" ]]
}

shell_job_is_running() {
	local pid="$1"
	local expected_identity="$2"
	local attempt
	local current_identity
	local job_pid
	local job_pids

	[[ -n "$pid" && -n "$expected_identity" ]] || return 1
	job_pids="$(jobs -p 2>/dev/null)" || return 1
	for job_pid in $job_pids; do
		if [[ "$job_pid" == "$pid" ]] && process_is_running "$pid"; then
			for ((attempt = 0; attempt < 3; attempt++)); do
				current_identity="$(process_start_time "$pid" 2>/dev/null || true)"
				if [[ "$current_identity" == "$expected_identity" ]]; then
					return 0
				fi
				process_is_running "$pid" || return 1
				sleep 0.01
			done
		fi
	done
	return 1
}

process_start_time() {
	local pid="$1"
	local stat_line
	local rest
	local -a fields

	[[ -n "$pid" && -r "/proc/$pid/stat" ]] || return 1
	IFS= read -r stat_line 2>/dev/null < "/proc/$pid/stat" || return 1
	rest="${stat_line##*) }"
	IFS=' ' read -r -a fields <<< "$rest"
	[[ ${#fields[@]} -ge 20 ]] || return 1
	printf '%s\n' "${fields[19]}"
}

process_identity_matches() {
	local pid="$1"
	local expected_identity="$2"
	local current_identity

	[[ -n "$pid" && -n "$expected_identity" ]] || return 1
	current_identity="$(process_start_time "$pid" 2>/dev/null || true)"
	[[ -n "$current_identity" && "$current_identity" == "$expected_identity" ]]
}

shell_job_spec_for_pid() {
	local pid="$1"
	local expected_identity="$2"
	local current_identity
	local job_number
	local job_pid
	local job_spec
	local line

	[[ -n "$pid" && -n "$expected_identity" ]] || return 1
	while IFS= read -r line; do
		line="${line#"${line%%[![:space:]]*}"}"
		job_spec="${line%%[[:space:]]*}"
		job_pid="${line#*[[:space:]]}"
		job_pid="${job_pid%%[[:space:]]*}"
		[[ "$job_pid" == "$pid" ]] || continue

		current_identity="$(process_start_time "$pid" 2>/dev/null || true)"
		[[ "$current_identity" == "$expected_identity" ]] || continue

		if [[ "$job_spec" =~ ^\[([0-9]+)\][+-]?$ ]]; then
			job_number="${BASH_REMATCH[1]}"
		else
			continue
		fi
		printf '%%%s\n' "$job_number"
		return 0
	done < <(jobs -l 2>/dev/null)
	return 1
}

signal_identified_process() {
	local pid="$1"
	local signal_name="$2"
	local expected_identity="$3"
	local attempt
	local job_spec=""

	[[ -n "$pid" && -n "$expected_identity" ]] || return 1
	process_is_running "$pid" || return 0
	for ((attempt = 0; attempt < 3; attempt++)); do
		if job_spec="$(shell_job_spec_for_pid "$pid" "$expected_identity")"; then
			break
		fi
		process_is_running "$pid" || return 0
		sleep 0.01
	done
	[[ -n "$job_spec" ]] || return 1
	if kill -s "$signal_name" -- "$job_spec" 2>/dev/null; then
		return 0
	fi
	process_is_running "$pid" || return 0
	return 1
}

signal_child_process() {
	local pid="$1"
	local signal_name="$2"
	local expected_identity="$3"

	[[ -n "$pid" ]] || return 0
	shell_job_is_running "$pid" "$expected_identity" || return 0
	signal_identified_process "$pid" "$signal_name" "$expected_identity"
}

children_are_running() {
	local wrapper_running=0
	local scrcpy_running=0

	shell_job_is_running "$WRAPPER_PID" "$WRAPPER_START_TIME" && wrapper_running=1
	shell_job_is_running "$SCRPYPID" "$SCRPYP_START_TIME" && scrcpy_running=1
	(( wrapper_running || scrcpy_running ))
}

start_watchdog() {
	local launcher_pid="$1"
	local target_pid="$2"
	local target_start_time="$3"

	"$WRAPPER" --watch-parent "$launcher_pid" "$target_pid" \
		"$target_start_time" &
	WATCHDOG_PID=$!
	WATCHDOG_START_TIME="$(process_start_time "$WATCHDOG_PID" 2>/dev/null || true)"
	if [[ -z "$WATCHDOG_START_TIME" ]]; then
		wait "$WATCHDOG_PID" 2>/dev/null || true
		WATCHDOG_PID=""
		WATCHDOG_START_TIME=""
		return 1
	fi

	sleep 0.05
	if shell_job_is_running "$WATCHDOG_PID" "$WATCHDOG_START_TIME"; then
		return 0
	fi
	if ! process_is_running "$target_pid"; then
		# Window selection will report the monitored process's exact status.
		return 0
	fi
	return 1
}

stop_watchdog() {
	local pid="$WATCHDOG_PID"
	local expected_identity="$WATCHDOG_START_TIME"
	local attempt

	if [[ -z "$pid" ]]; then
		WATCHDOG_START_TIME=""
		return 0
	fi
	if shell_job_is_running "$pid" "$expected_identity"; then
		signal_child_process "$pid" TERM "$expected_identity" || true
		for ((attempt = 0; attempt < 20; attempt++)); do
			shell_job_is_running "$pid" "$expected_identity" || break
			sleep 0.05
		done
		if shell_job_is_running "$pid" "$expected_identity"; then
			signal_child_process "$pid" KILL "$expected_identity" || true
		fi
	fi
	if shell_job_is_running "$pid" "$expected_identity"; then
		WATCHDOG_PID=""
		WATCHDOG_START_TIME=""
		return 1
	fi
	wait "$pid" 2>/dev/null || true
	WATCHDOG_PID=""
	WATCHDOG_START_TIME=""
	return 0
}

wait_for_process_to_exit() {
	local pid="$1"
	local expected_identity="$2"
	local attempt

	for ((attempt = 0; attempt < 50; attempt++)); do
		shell_job_is_running "$pid" "$expected_identity" || return 0
		sleep 0.1
	done
	! shell_job_is_running "$pid" "$expected_identity"
}

cleanup() {
	local status=$?
	local attempt
	local final_status="$status"
	local cleanup_failed=0
	local wrapper_status=0

	trap - EXIT

	stop_watchdog || cleanup_failed=1

	if (( FIRST_WAS_SCRPYPY == 1 && FIRST_STATUS == 0 )) \
			&& [[ -n "$WRAPPER_PID" ]]; then
		# Let the wrapper observe the normal scrcpy exit and report any
		# simultaneous wrapper error before asking it to terminate.
		for ((attempt = 0; attempt < 30; attempt++)); do
			shell_job_is_running "$WRAPPER_PID" "$WRAPPER_START_TIME" || break
			sleep 0.1
		done
	fi

	signal_child_process "$WRAPPER_PID" TERM "$WRAPPER_START_TIME" \
		|| cleanup_failed=1
	signal_child_process "$SCRPYPID" TERM "$SCRPYP_START_TIME" \
		|| cleanup_failed=1

	for ((attempt = 0; attempt < 50; attempt++)); do
		if ! children_are_running; then
			break
		fi
		sleep 0.1
	done

	if children_are_running; then
		signal_child_process "$WRAPPER_PID" KILL "$WRAPPER_START_TIME" \
			|| cleanup_failed=1
		signal_child_process "$SCRPYPID" KILL "$SCRPYP_START_TIME" \
			|| cleanup_failed=1
		for ((attempt = 0; attempt < 20; attempt++)); do
			if ! children_are_running; then
				break
			fi
			sleep 0.1
		done
	fi

	if [[ -n "$WRAPPER_PID" ]]; then
		if ! wait_for_process_to_exit "$WRAPPER_PID" "$WRAPPER_START_TIME"; then
			cleanup_failed=1
		else
			wait "$WRAPPER_PID" 2>/dev/null || wrapper_status=$?
		fi
	fi
	if [[ -n "$SCRPYPID" ]]; then
		if ! wait_for_process_to_exit "$SCRPYPID" "$SCRPYP_START_TIME"; then
			cleanup_failed=1
		else
			wait "$SCRPYPID" 2>/dev/null || true
		fi
	fi

	if (( FIRST_WAS_SCRPYPY == 1 && FIRST_STATUS == 0 )); then
		if (( wrapper_status != 0 && wrapper_status != 125
				&& wrapper_status != 143 )); then
			final_status="$wrapper_status"
		fi
	fi

	if (( cleanup_failed != 0 && final_status == 0 )); then
		final_status=1
	fi

	exit "$final_status"
}

wait_for_first_child() {
	if wait -n -p FIRST_PID "$SCRPYPID" "$WRAPPER_PID"; then
		FIRST_STATUS=0
	else
		FIRST_STATUS=$?
	fi
	FIRST_PID="${FIRST_PID:-}"
	if [[ -z "$FIRST_PID" ]]; then
		echo "Could not determine which child exited first" >&2
		return 1
	fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

"$SCRCPY_BIN" \
	"$@" \
	--no-audio \
	--max-size="$MAX_SIZE" \
	--max-fps=60 \
	--render-fit=unscaled \
	--window-height="$CHILD_HEIGHT" \
	--window-borderless \
	--window-title=gtk-scrcpy-wrapper &
SCRPYPID=$!
SCRPYP_START_TIME="$(process_start_time "$SCRPYPID" 2>/dev/null || true)"
if [[ -z "$SCRPYP_START_TIME" ]]; then
	echo "Could not identify the launched scrcpy process" >&2
	exit 1
fi

# The wrapper is not running yet while the scrcpy window is being selected.
# Keep a small parent-death watchdog active during that interval.
if ! start_watchdog "$$" "$SCRPYPID" "$SCRPYP_START_TIME"; then
	echo "Could not start the scrcpy parent-death watchdog" >&2
	exit 1
fi

window_geometry() {
	xwininfo -id "$1" 2>/dev/null \
		| awk '/Width:/ { width = $2 } /Height:/ { height = $2 }
			END { if (width && height) print width "x" height }' || true
}

window_position() {
	xwininfo -id "$1" 2>/dev/null \
		| awk '/Absolute upper-left X:/ { x = $4 }
			/Absolute upper-left Y:/ { y = $4 }
			END { if (x != "" && y != "") print x "," y }' || true
}

find_scrcpy_window() {
	local candidate
	local window_pid
	local window_class
	local geometry
	local width
	local height
	local area
	local best_candidate=""
	local best_area=0

	process_identity_matches "$SCRPYPID" "$SCRPYP_START_TIME" || return 1

	while IFS= read -r candidate; do
		[[ "$candidate" =~ ^[0-9]+$ ]] || continue

		window_pid="$(xdotool getwindowpid "$candidate" 2>/dev/null || true)"
		[[ "$window_pid" == "$SCRPYPID" ]] || continue

		window_class="$(xprop -id "$candidate" WM_CLASS 2>/dev/null \
			| sed -n 's/.*= "\([^"]*\)", "\([^"]*\)".*/\1|\2/p')"
		[[ "$window_class" == "scrcpy|scrcpy" ]] || continue

		if ! xwininfo -id "$candidate" 2>/dev/null \
				| grep -q 'Map State: IsViewable'; then
			continue
		fi

		geometry="$(window_geometry "$candidate")"
		[[ -n "$geometry" ]] || continue
		IFS=x read -r width height <<< "$geometry"
		area=$((width * height))

		if (( area > best_area )); then
			best_area=$area
			best_candidate="$candidate"
		fi
	done < <(xdotool search --all --pid "$SCRPYPID" 2>/dev/null)

	process_identity_matches "$SCRPYPID" "$SCRPYP_START_TIME" || return 1
	[[ -n "$best_candidate" ]] || return 1
	printf '%s\n' "$best_candidate"
}

# Wait for scrcpy's final, mapped X11 window. SDL creates a hidden window
# before the first video frame and changes its final size when that frame
# arrives, so selecting the first title match is not safe.
WINID=""
last_signature=""
stable_count=0

for ((attempt = 0; attempt < 300; attempt++)); do
	if ! process_is_running "$SCRPYPID"; then
		scrcpy_status=0
		wait "$SCRPYPID" 2>/dev/null || scrcpy_status=$?
		SCRPYPID=""
		echo "scrcpy exited before creating its window" >&2
		if (( scrcpy_status == 0 )); then
			scrcpy_status=1
		fi
		exit "$scrcpy_status"
	fi
	if ! process_identity_matches "$SCRPYPID" "$SCRPYP_START_TIME"; then
		scrcpy_status=0
		wait "$SCRPYPID" 2>/dev/null || scrcpy_status=$?
		SCRPYPID=""
		echo "scrcpy process identity changed before creating its window" >&2
		if (( scrcpy_status == 0 )); then
			scrcpy_status=1
		fi
		exit "$scrcpy_status"
	fi

	candidate="$(find_scrcpy_window || true)"
	if [[ -n "$candidate" ]]; then
		geometry="$(window_geometry "$candidate")"
		position="$(window_position "$candidate")"
		signature="$candidate:$geometry:$position"

		if [[ "$signature" == "$last_signature" && -n "$geometry" \
				&& -n "$position" ]]; then
			stable_count=$((stable_count + 1))
		else
			last_signature="$signature"
			stable_count=0
		fi

		if (( stable_count >= 5 )); then
			WINID="$candidate"
			break
		fi
	fi

	sleep 0.1
done

if ! process_identity_matches "$SCRPYPID" "$SCRPYP_START_TIME"; then
	scrcpy_status=0
	wait "$SCRPYPID" 2>/dev/null || scrcpy_status=$?
	SCRPYPID=""
	echo "scrcpy process identity changed before wrapping its window" >&2
	if (( scrcpy_status == 0 )); then
		scrcpy_status=1
	fi
	exit "$scrcpy_status"
fi

if [[ -z "$WINID" ]]; then
	echo "Could not find a stable scrcpy window" >&2
	exit 1
fi

printf -v WINID_HEX '0x%x' "$WINID"
echo "Using scrcpy window $WINID_HEX (decimal $WINID)" >&2

"$WRAPPER" \
	"$WINID" \
	"$SCRPYPID" \
	"$SCRPYP_START_TIME" \
	"$WRAPPER_WIDTH" \
	"$WRAPPER_HEIGHT" \
	"$SCROLL_STEP" &
WRAPPER_PID=$!
WRAPPER_START_TIME="$(process_start_time "$WRAPPER_PID" 2>/dev/null || true)"

wait_for_first_child
STATUS="$FIRST_STATUS"

if [[ "$FIRST_PID" == "$WRAPPER_PID" \
		&& "$STATUS" == "$WRAPPER_SCRCPY_EXIT_STATUS" ]]; then
	scrcpy_status=0
	wait "$SCRPYPID" 2>/dev/null || scrcpy_status=$?
	STATUS="$scrcpy_status"
	SCRPYPID=""
fi

if [[ "$FIRST_PID" == "$SCRPYPID" ]]; then
	FIRST_WAS_SCRPYPY=1
	SCRPYPID=""
else
	FIRST_WAS_SCRPYPY=0
	WRAPPER_PID=""
fi

exit "$STATUS"
