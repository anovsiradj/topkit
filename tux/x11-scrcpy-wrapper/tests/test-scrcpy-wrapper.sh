#!/usr/bin/env bash

set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_DIR="$(cd "$TESTS_DIR/.." && pwd)"
ROOT="$(cd "$TOOL_DIR/../.." && pwd)"
if ! BUILD_DIR="$(mktemp -d "$ROOT/tmp/x11-scrcpy-wrapper-tests.XXXXXX")"; then
	echo "Could not create the test build directory under tmp/" >&2
	exit 1
fi
FAKE="$BUILD_DIR/fake-scrcpy-bin"
SCRIPT="$TOOL_DIR/x11-scrcpy-wrapper.sh"
SOURCE="$TOOL_DIR/x11-scrcpy-wrapper.c"
WRAPPER="$TOOL_DIR/x11-scrcpy-wrapper"
TEST_WRAPPER="$BUILD_DIR/x11-scrcpy-wrapper-test"
FAILED_GRAB_WRAPPER="$BUILD_DIR/x11-scrcpy-wrapper-failed-grab-test"
UNIT_TEST="$BUILD_DIR/unit-scroll-test"
SEND_BUTTON="$BUILD_DIR/send-button"
SEND_SCROLL_DRAG="$BUILD_DIR/send-scroll-drag"
SEND_SCROLL_EVENT="$BUILD_DIR/send-scroll-event"
SEND_WM_DELETE="$BUILD_DIR/send-wm-delete"
REPARENT_WINDOW="$BUILD_DIR/reparent-window"
OUT="$ROOT/tmp/scrcpy-wrapper-tests.out"
: > "$OUT"

failures=0
launcher_pid=""
wrapper_pid=""
fake_pid=""
wrapper_id=""
child_id=""
mismatch_pid=""

log() {
	printf '%s\n' "$*" | tee -a "$OUT"
}

fail() {
	log "FAIL: $*"
	failures=$((failures + 1))
}

pass() {
	log "PASS: $*"
}

cleanup() {
	[[ -z "$mismatch_pid" ]] || kill -TERM "$mismatch_pid" 2>/dev/null || true
	[[ -z "$fake_pid" ]] || kill -TERM "$fake_pid" 2>/dev/null || true
	[[ -z "$wrapper_pid" ]] || kill -TERM "$wrapper_pid" 2>/dev/null || true
	[[ -z "$launcher_pid" ]] || kill -TERM "$launcher_pid" 2>/dev/null || true
}
trap cleanup EXIT

wait_for_exit() {
	local pid="$1"
	local attempts="${2:-100}"

	for ((attempt = 0; attempt < attempts; attempt++)); do
		kill -0 "$pid" 2>/dev/null || return 0
		sleep 0.1
	done
	return 1
}

build_test_helpers() {
	local compiler="${CC:-cc}"
	local flags=(-std=c11 -O2 -Wall -Wextra -Wpedantic)

	"$compiler" "${flags[@]}" -o "$FAKE" \
		"$TESTS_DIR/helpers/fake-scrcpy.c" -lX11 || return 1
	"$compiler" "${flags[@]}" -o "$SEND_BUTTON" \
		"$TESTS_DIR/helpers/send-button.c" -lX11 || return 1
	"$compiler" "${flags[@]}" -o "$SEND_SCROLL_DRAG" \
		"$TESTS_DIR/helpers/send-scroll-drag.c" -lX11 || return 1
	"$compiler" "${flags[@]}" -o "$SEND_SCROLL_EVENT" \
		"$TESTS_DIR/helpers/send-scroll-event.c" -lX11 || return 1
	"$compiler" "${flags[@]}" -o "$SEND_WM_DELETE" \
		"$TESTS_DIR/helpers/send-wm-delete.c" -lX11 || return 1
	"$compiler" "${flags[@]}" -o "$REPARENT_WINDOW" \
		"$TESTS_DIR/helpers/reparent-window.c" -lX11 || return 1
	"$compiler" "${flags[@]}" -o "$UNIT_TEST" \
		"$TESTS_DIR/unit-scroll-test.c" -lX11 -lXi || return 1
	chmod 755 "$FAKE" "$SEND_BUTTON" "$SEND_SCROLL_DRAG" \
		"$SEND_SCROLL_EVENT" "$SEND_WM_DELETE" "$REPARENT_WINDOW" \
		"$UNIT_TEST"
}

run_unit_tests() {
	local output

	if output="$("$UNIT_TEST" 2>&1)"; then
		while IFS= read -r line; do
			log "$line"
		done <<< "$output"
		return 0
	fi
	while IFS= read -r line; do
		log "$line"
	done <<< "$output"
	fail "unit tests failed"
	return 1
}

child_pid_by_executable() {
	local parent_pid="$1"
	local executable="$2"
	local excluded_first_argument="${3:-}"
	local candidate
	local command_line
	local first_argument
	local resolved_executable
	local -a arguments

	executable="$(readlink -f "$executable" 2>/dev/null || true)"
	for candidate in $(pgrep -P "$parent_pid" 2>/dev/null); do
		resolved_executable="$(readlink -f "/proc/$candidate/exe" 2>/dev/null || true)"
		[[ "$resolved_executable" == "$executable" ]] || continue
		command_line="$(tr '\0' ' ' < "/proc/$candidate/cmdline" 2>/dev/null || true)"
		read -r -a arguments <<< "$command_line"
		first_argument="${arguments[1]:-}"
		if [[ -n "$excluded_first_argument" \
				&& "$first_argument" == "$excluded_first_argument" ]]; then
			continue
		fi
		printf '%s\n' "$candidate"
		return 0
	done
	return 1
}

start_launcher() {
	local delay="${1:-0}"
	local attempt

	rm -f "$ROOT/tmp/scrcpy-wrapper-test-run.out"
	FAKE_SCRCPY_DELAY="$delay" \
		SCRCPY_BIN="$FAKE" \
		SCRCPY_SCROLL_WIDTH=480 \
		SCRCPY_SCROLL_HEIGHT=360 \
		"$SCRIPT" >"$ROOT/tmp/scrcpy-wrapper-test-run.out" 2>&1 &
	launcher_pid=$!
	wrapper_pid=""
	fake_pid=""
	wrapper_id=""
	child_id=""

	for ((attempt = 0; attempt < 150; attempt++)); do
		wrapper_pid="$(child_pid_by_executable "$launcher_pid" "$WRAPPER" \
			"--watch-parent" || true)"
		fake_pid="$(child_pid_by_executable "$launcher_pid" "$FAKE" || true)"
		if [[ -n "$wrapper_pid" ]]; then
			wrapper_id="$(xdotool search --all --pid "$wrapper_pid" \
				--class '^X11ScrcpyWrapper$' 2>/dev/null | head -1)"
		fi
		if [[ -n "$fake_pid" ]]; then
			child_id="$(xdotool search --all --pid "$fake_pid" 2>/dev/null | head -1)"
		fi
		if [[ -n "$wrapper_id" && -n "$child_id" ]]; then
			return 0
		fi
		kill -0 "$launcher_pid" 2>/dev/null || return 1
		sleep 0.1
	done
	return 1
}

relative_position() {
	xwininfo -id "$1" | awk '
		/Relative upper-left X:/ { x = $4 }
		/Relative upper-left Y:/ { y = $4 }
		END { print x "," y }
	'
}

parent_id() {
	xwininfo -id "$1" -tree | awk '/Parent window id:/ { print $4; exit }'
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

map_state() {
	xwininfo -id "$1" | awk '/Map State:/ { print $3; exit }'
}

find_scrollbar() {
	local class="$1"
	local orientation="$2"
	local id
	local width
	local height

	for id in $(xdotool search --all --class "^$class$" 2>/dev/null); do
		width="$(xwininfo -id "$id" 2>/dev/null | awk '/Width:/ { print $2; exit }')"
		height="$(xwininfo -id "$id" 2>/dev/null | awk '/Height:/ { print $2; exit }')"
		if [[ "$orientation" == "vertical" && "$width" == "16" && "$height" -gt 16 ]]; then
			printf '%s\n' "$id"
			return 0
		fi
		if [[ "$orientation" == "horizontal" && "$height" == "16" && "$width" -gt 16 ]]; then
			printf '%s\n' "$id"
			return 0
		fi
	done
	return 1
}

find_scrollbar_thumb() {
	local orientation="$1"
	local id
	local width
	local height

	for id in $(xdotool search --all --class '^X11ScrcpyWrapperThumb$' 2>/dev/null); do
		width="$(xwininfo -id "$id" 2>/dev/null | awk '/Width:/ { print $2; exit }')"
		height="$(xwininfo -id "$id" 2>/dev/null | awk '/Height:/ { print $2; exit }')"
		if [[ "$orientation" == "vertical" && "$width" == "12" && "$height" -gt 12 ]]; then
			printf '%s\n' "$id"
			return 0
		fi
		if [[ "$orientation" == "horizontal" && "$height" == "12" && "$width" -gt 12 ]]; then
			printf '%s\n' "$id"
			return 0
		fi
	done
	return 1
}

build_drag_test_wrapper() {
	local success_source="$BUILD_DIR/x11-scrcpy-wrapper-test.c"
	local failed_source="$BUILD_DIR/x11-scrcpy-wrapper-failed-grab-test.c"

	sed '/^static bool grab_scrollbar_pointer(Window window) {$/,/^}$/c\
static bool grab_scrollbar_pointer(Window window) {\
	(void) window;\
	return true;\
}' "$SOURCE" > "$success_source" || return 1
	sed '/^static bool grab_scrollbar_pointer(Window window) {$/,/^}$/c\
static bool grab_scrollbar_pointer(Window window) {\
	(void) window;\
	return false;\
}' "$SOURCE" > "$failed_source" || return 1
	"${CC:-cc}" -std=c11 -O2 -Wall -Wextra -Wpedantic \
		-o "$TEST_WRAPPER" "$success_source" -lX11 -lXi || return 1
	"${CC:-cc}" -std=c11 -O2 -Wall -Wextra -Wpedantic \
		-o "$FAILED_GRAB_WRAPPER" "$failed_source" -lX11 -lXi || return 1
	chmod 755 "$TEST_WRAPPER" "$FAILED_GRAB_WRAPPER"
}

if ! build_test_helpers; then
	fail "could not build the test helpers"
	exit 1
fi

run_unit_tests || true

if ! build_drag_test_wrapper; then
	fail "could not build the synthetic drag-test wrapper"
	exit 1
fi

# Normal lifecycle, hierarchy, WM properties, scrollbars, bounds, and resize.
if start_launcher; then
	parent_hex="$(parent_id "$child_id")"
	parent_decimal=$((parent_hex))
	wrapper_decimal=$((wrapper_id))
	if [[ "$parent_decimal" == "$wrapper_decimal" ]]; then
		pass "scrcpy child is reparented into the wrapper"
	else
		fail "scrcpy child parent $parent_decimal is not wrapper $wrapper_decimal"
	fi

	if xprop -id "$wrapper_id" WM_PROTOCOLS 2>/dev/null | grep -q WM_DELETE_WINDOW \
			&& xprop -id "$wrapper_id" _NET_WM_WINDOW_TYPE 2>/dev/null \
				| grep -q _NET_WM_WINDOW_TYPE_NORMAL \
			&& xprop -id "$wrapper_id" WM_STATE 2>/dev/null | grep -q Normal; then
		pass "wrapper has normal WM state, type, and WM_DELETE_WINDOW"
	else
		fail "wrapper WM properties are incomplete"
	fi

	vertical_track=""
	vertical_thumb=""
	horizontal_track=""
	horizontal_thumb=""
	for _ in $(seq 1 50); do
		vertical_track="$(find_scrollbar X11ScrcpyWrapperTrack vertical || true)"
		vertical_thumb="$(find_scrollbar_thumb vertical || true)"
		horizontal_track="$(find_scrollbar X11ScrcpyWrapperTrack horizontal || true)"
		horizontal_thumb="$(find_scrollbar_thumb horizontal || true)"
		[[ -n "$vertical_track" && -n "$vertical_thumb" \
			&& -n "$horizontal_track" && -n "$horizontal_thumb" ]] && break
		sleep 0.05
	done
	if [[ -n "$vertical_track" && -n "$vertical_thumb" \
			&& -n "$horizontal_track" && -n "$horizontal_thumb" ]]; then
		vertical_track_parent="$(( $(parent_id "$vertical_track") ))"
		vertical_thumb_parent="$(( $(parent_id "$vertical_thumb") ))"
		horizontal_track_parent="$(( $(parent_id "$horizontal_track") ))"
		horizontal_thumb_parent="$(( $(parent_id "$horizontal_thumb") ))"
		if [[ "$vertical_track_parent" == "$wrapper_decimal" \
				&& "$vertical_thumb_parent" == "$vertical_track" \
				&& "$horizontal_track_parent" == "$wrapper_decimal" \
				&& "$horizontal_thumb_parent" == "$horizontal_track" \
				&& "$(map_state "$vertical_track")" == "IsViewable" \
				&& "$(map_state "$horizontal_track")" == "IsViewable" ]]; then
			pass "wrapper contains vertical and horizontal scrollbar tracks and thumbs"
		else
			fail "embedded scrollbar windows are incomplete"
		fi
	else
		fail "embedded scrollbar windows are incomplete"
	fi

	if [[ -x "$SEND_BUTTON" && -n "$vertical_track" ]]; then
		"$SEND_BUTTON" "$vertical_track" 300
		scroll_position=""
		for _ in $(seq 1 50); do
			scroll_position="$(relative_position "$child_id")"
			[[ "$scroll_position" == "0,-344" ]] && break
			sleep 0.05
		done
		thumb_position="$(xwininfo -id "$vertical_thumb" 2>/dev/null \
			| awk '/Relative upper-left Y:/ { print $4; exit }')"
		if [[ "$scroll_position" == "0,-344" && "$thumb_position" -gt 0 ]]; then
			pass "scrollbar track scrolls the child and updates its thumb"
		else
			fail "scrollbar track did not scroll the child (position=$scroll_position, thumb=$thumb_position)"
		fi

		"$SEND_BUTTON" "$vertical_track" 0
		scroll_position=""
		for _ in $(seq 1 50); do
			scroll_position="$(relative_position "$child_id")"
			[[ "$scroll_position" == "0,0" ]] && break
			sleep 0.05
		done
		if [[ "$scroll_position" == "0,0" ]]; then
			pass "scrollbar track scrolls back toward the start"
		else
			fail "scrollbar track did not scroll back (position=$scroll_position)"
		fi

		if [[ -n "$horizontal_track" ]]; then
			"$SEND_BUTTON" "$horizontal_track" 300
			scroll_position=""
			for _ in $(seq 1 50); do
				scroll_position="$(relative_position "$child_id")"
				[[ "$scroll_position" == "-368,0" ]] && break
				sleep 0.05
			done
			thumb_position="$(xwininfo -id "$horizontal_thumb" 2>/dev/null \
				| awk '/Relative upper-left X:/ { print $4; exit }')"
			if [[ "$scroll_position" == "-368,0" && "$thumb_position" -gt 0 ]]; then
				pass "horizontal scrollbar track scrolls the child and updates its thumb"
			else
				fail "horizontal scrollbar track did not scroll the child (position=$scroll_position, thumb=$thumb_position)"
			fi

			"$SEND_BUTTON" "$horizontal_track" 0
			scroll_position=""
			for _ in $(seq 1 50); do
				scroll_position="$(relative_position "$child_id")"
				[[ "$scroll_position" == "0,0" ]] && break
				sleep 0.05
			done
			if [[ "$scroll_position" == "0,0" ]]; then
				pass "horizontal scrollbar track scrolls back toward the start"
			else
				fail "horizontal scrollbar track did not scroll back (position=$scroll_position)"
			fi
		else
			fail "horizontal scrollbar track is unavailable"
		fi
	else
		fail "scrollbar track test helper is unavailable"
	fi

	xdotool windowsize "$child_id" 400 300
	resized_position=""
	resized_vertical_state=""
	for _ in $(seq 1 50); do
		resized_position="$(relative_position "$child_id")"
		resized_vertical_state="$(map_state "$vertical_track")"
		[[ "$resized_position" == "40,30" \
			&& "$resized_vertical_state" == "IsUnMapped" ]] && break
		sleep 0.05
	done
	if [[ "$resized_position" == "40,30" \
			&& "$resized_vertical_state" == "IsUnMapped" ]]; then
		pass "scrollbars hide and the child centers when content fits"
	else
		fail "scrollbar overflow update failed (position=$resized_position, vertical=$resized_vertical_state)"
	fi

	xdotool windowsize "$child_id" 832 1920
	restored_position=""
	restored_vertical_state=""
	for _ in $(seq 1 50); do
		restored_position="$(relative_position "$child_id")"
		restored_vertical_state="$(map_state "$vertical_track")"
		[[ "$restored_position" == "0,0" \
			&& "$restored_vertical_state" == "IsViewable" ]] && break
		sleep 0.05
	done
	if [[ "$restored_position" == "0,0" \
			&& "$restored_vertical_state" == "IsViewable" ]]; then
		pass "scrollbars return when the child overflows again"
	else
		fail "scrollbar overflow restoration failed (position=$restored_position, vertical=$restored_vertical_state)"
	fi

	position=""
	for _ in $(seq 1 50); do
		position="$(relative_position "$child_id")"
		[[ "$position" == "0,0" ]] && break
		sleep 0.05
	done
	if [[ "$position" == "0,0" ]]; then
		pass "child starts at the viewport origin"
	else
		fail "unexpected initial child position $position"
	fi

	xdotool windowmove "$child_id" 100 100
	sleep 0.4
	position="$(relative_position "$child_id")"
	if [[ "$position" == "0,0" ]]; then
		pass "child is clamped at the upper movement bound"
	else
		fail "child upper-bound clamp produced $position"
	fi

	xdotool windowmove "$child_id" -1000 -3000
	sleep 0.4
	position="$(relative_position "$child_id")"
	if [[ "$position" == "-368,-1576" ]]; then
		pass "child is clamped at the lower movement bound"
	else
		fail "child lower-bound clamp produced $position"
	fi

	xdotool windowsize "$wrapper_id" 640 480
	sleep 0.7
	xdotool windowmove "$child_id" -1000 -3000
	sleep 0.4
	position="$(relative_position "$child_id")"
	if [[ "$position" == "-208,-1456" ]]; then
		pass "movement bounds follow the resized wrapper"
	else
		fail "resized movement bounds produced $position"
	fi

	"$SEND_WM_DELETE" "$wrapper_id"
	if wait_for_exit "$launcher_pid"; then
		wait "$launcher_pid"
		status=$?
		if [[ "$status" == 0 ]]; then
			pass "WM close exits the launcher successfully"
		else
			fail "WM close returned status $status"
		fi
	else
		fail "launcher remained alive after WM close"
	fi
	launcher_pid=""
	wrapper_pid=""
	fake_pid=""
else
	fail "could not start launcher"
fi

# Drag-state tests use a direct wrapper with a forced successful pointer grab.
# The production wrapper requires a real successful XGrabPointer before dragging.
"$FAKE" >"$ROOT/tmp/scrcpy-wrapper-drag-fake.out" 2>&1 &
fake_pid=$!
for _ in $(seq 1 50); do
	[[ -s "$ROOT/tmp/scrcpy-wrapper-drag-fake.out" ]] && break
	sleep 0.05
done
child_id="$(awk '{print $2}' "$ROOT/tmp/scrcpy-wrapper-drag-fake.out" \
	| sed 's/window=//')"
fake_start_time="$(process_start_time "$fake_pid")"
"$TEST_WRAPPER" "$child_id" "$fake_pid" "$fake_start_time" 480 360 50 \
	>"$ROOT/tmp/scrcpy-wrapper-drag-wrapper.out" 2>&1 &
wrapper_pid=$!
vertical_track=""
vertical_thumb=""
horizontal_track=""
horizontal_thumb=""
for _ in $(seq 1 100); do
	vertical_track="$(find_scrollbar X11ScrcpyWrapperTrack vertical || true)"
	vertical_thumb="$(find_scrollbar_thumb vertical || true)"
	horizontal_track="$(find_scrollbar X11ScrcpyWrapperTrack horizontal || true)"
	horizontal_thumb="$(find_scrollbar_thumb horizontal || true)"
	if [[ -n "$vertical_track" && -n "$vertical_thumb" \
			&& -n "$horizontal_track" && -n "$horizontal_thumb" ]]; then
		break
	fi
	sleep 0.05
done
if [[ -n "$vertical_track" && -n "$vertical_thumb" \
		&& -n "$horizontal_track" && -n "$horizontal_thumb" ]]; then
	"$SEND_SCROLL_DRAG" "$vertical_thumb" "$vertical_track" 5 250
	drag_position=""
	for _ in $(seq 1 50); do
		drag_position="$(relative_position "$child_id")"
		[[ "$drag_position" == "0,-1364" ]] && break
		sleep 0.05
	done
	if [[ "$drag_position" == "0,-1364" ]]; then
		pass "scrollbar thumb drags the child to the requested position"
	else
		fail "scrollbar thumb drag produced $drag_position"
	fi

	"$SEND_SCROLL_DRAG" "$vertical_thumb" "$vertical_track" 5 5
	drag_position=""
	for _ in $(seq 1 50); do
		drag_position="$(relative_position "$child_id")"
		[[ "$drag_position" == "0,0" ]] && break
		sleep 0.05
	done
	if [[ "$drag_position" == "0,0" ]]; then
		pass "scrollbar thumb can return to the start"
	else
		fail "scrollbar thumb did not return to the start ($drag_position)"
	fi

	"$SEND_SCROLL_DRAG" "$horizontal_thumb" "$horizontal_track" 400 5
	drag_position=""
	for _ in $(seq 1 50); do
		drag_position="$(relative_position "$child_id")"
		[[ "$drag_position" == "-368,0" ]] && break
		sleep 0.05
	done
	if [[ "$drag_position" == "-368,0" ]]; then
		pass "horizontal scrollbar thumb drags the child"
	else
		fail "horizontal scrollbar thumb drag produced $drag_position"
	fi

	"$SEND_SCROLL_DRAG" "$horizontal_thumb" "$horizontal_track" 5 5
	drag_position=""
	for _ in $(seq 1 50); do
		drag_position="$(relative_position "$child_id")"
		[[ "$drag_position" == "0,0" ]] && break
		sleep 0.05
	done
	if [[ "$drag_position" == "0,0" ]]; then
		pass "horizontal scrollbar thumb can return to the start"
	else
		fail "horizontal scrollbar thumb did not return to the start ($drag_position)"
	fi

	"$SEND_SCROLL_EVENT" "$vertical_thumb" press 0 5 5
	sleep 0.1
	xdotool windowsize "$child_id" 400 300
	for _ in $(seq 1 50); do
		[[ "$(map_state "$vertical_track")" == "IsUnMapped" ]] && break
		sleep 0.05
	done
	xdotool windowsize "$child_id" 832 1920
	for _ in $(seq 1 50); do
		[[ "$(map_state "$vertical_track")" == "IsViewable" ]] && break
		sleep 0.05
	done
	stale_drag_position="$(relative_position "$child_id")"
	"$SEND_SCROLL_EVENT" "$vertical_track" motion 256 5 250
	sleep 0.1
	stale_drag_position_after="$(relative_position "$child_id")"
	"$SEND_SCROLL_EVENT" "$vertical_track" release 256 5 5
	if [[ "$stale_drag_position" == "0,0" \
			&& "$stale_drag_position_after" == "0,0" ]]; then
		pass "hiding a scrollbar cancels its active drag"
	else
		fail "stale scrollbar drag moved the child ($stale_drag_position -> $stale_drag_position_after)"
	fi
else
	fail "could not start the synthetic drag-test wrapper"
fi
kill -TERM "$wrapper_pid" 2>/dev/null || true
wait "$wrapper_pid" 2>/dev/null || true
if kill -0 "$fake_pid" 2>/dev/null; then
	kill -TERM "$fake_pid" 2>/dev/null || true
fi
wait "$fake_pid" 2>/dev/null || true
wrapper_pid=""
fake_pid=""

# A failed pointer grab must not leave a drag active.
"$FAKE" >"$ROOT/tmp/scrcpy-wrapper-failed-grab-fake.out" 2>&1 &
fake_pid=$!
for _ in $(seq 1 50); do
	[[ -s "$ROOT/tmp/scrcpy-wrapper-failed-grab-fake.out" ]] && break
	sleep 0.05
done
child_id="$(awk '{print $2}' "$ROOT/tmp/scrcpy-wrapper-failed-grab-fake.out" \
	| sed 's/window=//')"
fake_start_time="$(process_start_time "$fake_pid")"
"$FAILED_GRAB_WRAPPER" "$child_id" "$fake_pid" "$fake_start_time" 480 360 50 \
	>"$ROOT/tmp/scrcpy-wrapper-failed-grab-wrapper.out" 2>&1 &
wrapper_pid=$!
vertical_track=""
vertical_thumb=""
for _ in $(seq 1 100); do
	vertical_track="$(find_scrollbar X11ScrcpyWrapperTrack vertical || true)"
	vertical_thumb="$(find_scrollbar_thumb vertical || true)"
	[[ -n "$vertical_track" && -n "$vertical_thumb" ]] && break
	sleep 0.05
done
if [[ -n "$vertical_track" && -n "$vertical_thumb" ]]; then
	"$SEND_SCROLL_EVENT" "$vertical_thumb" press 0 5 5
	sleep 0.1
	failed_grab_position="$(relative_position "$child_id")"
	"$SEND_SCROLL_EVENT" "$vertical_track" motion 256 5 250
	sleep 0.1
	failed_grab_position_after="$(relative_position "$child_id")"
	"$SEND_SCROLL_EVENT" "$vertical_track" release 256 5 5
	if [[ "$failed_grab_position" == "0,0" \
			&& "$failed_grab_position_after" == "0,0" ]]; then
		pass "failed pointer grab does not activate a scrollbar drag"
	else
		fail "failed pointer grab left an active drag ($failed_grab_position -> $failed_grab_position_after)"
	fi
else
	fail "could not start the failed-grab test wrapper"
fi
kill -TERM "$wrapper_pid" 2>/dev/null || true
wait "$wrapper_pid" 2>/dev/null || true
if kill -0 "$fake_pid" 2>/dev/null; then
	kill -TERM "$fake_pid" 2>/dev/null || true
fi
wait "$fake_pid" 2>/dev/null || true
wrapper_pid=""
fake_pid=""

# Exiting scrcpy must close the wrapper and launcher.
if start_launcher; then
	kill -TERM "$fake_pid"
	if wait_for_exit "$launcher_pid"; then
		wait "$launcher_pid"
		status=$?
		if [[ "$status" == 0 ]] && ! kill -0 "$wrapper_pid" 2>/dev/null; then
			pass "scrcpy exit closes the wrapper"
		else
			fail "scrcpy-exit lifecycle returned status $status"
		fi
	else
		fail "launcher remained alive after scrcpy exited"
	fi
	launcher_pid=""
	wrapper_pid=""
	fake_pid=""
else
	fail "could not start launcher for scrcpy-exit test"
fi

# A crashing scrcpy must close the wrapper and preserve the crash status.
if start_launcher; then
	kill -KILL "$fake_pid"
	if wait_for_exit "$launcher_pid"; then
		wait "$launcher_pid"
		status=$?
		if [[ "$status" == 137 ]] && ! kill -0 "$wrapper_pid" 2>/dev/null; then
			pass "scrcpy crash closes the wrapper and propagates its status"
		else
			fail "scrcpy-crash lifecycle returned status $status"
		fi
	else
		fail "launcher remained alive after scrcpy crashed"
	fi
	launcher_pid=""
	wrapper_pid=""
	fake_pid=""
else
	fail "could not start launcher for scrcpy-crash test"
fi

# An external reparent must fail loudly and terminate both children.
if start_launcher; then
	"$REPARENT_WINDOW" "$child_id"
	if wait_for_exit "$launcher_pid"; then
		wait "$launcher_pid"
		status=$?
		if [[ "$status" != 0 ]] && ! kill -0 "$wrapper_pid" 2>/dev/null; then
			pass "external reparenting fails and closes the wrapper"
		else
			fail "external reparenting returned status $status"
		fi
	else
		fail "launcher remained alive after external reparenting"
	fi
	launcher_pid=""
	wrapper_pid=""
	fake_pid=""
else
	fail "could not start launcher for external-reparent test"
fi

# A window must be bound to the supplied scrcpy PID.
"$FAKE" >"$ROOT/tmp/scrcpy-wrapper-mismatch-fake.out" 2>&1 &
fake_pid=$!
for _ in $(seq 1 50); do
	[[ -s "$ROOT/tmp/scrcpy-wrapper-mismatch-fake.out" ]] && break
	sleep 0.05
done
child_id="$(awk '{print $2}' "$ROOT/tmp/scrcpy-wrapper-mismatch-fake.out" \
	| sed 's/window=//')"
sleep 30 &
mismatch_pid=$!
mismatch_start_time="$(process_start_time "$mismatch_pid")"
before_parent="$(parent_id "$child_id")"
"$WRAPPER" "$child_id" "$mismatch_pid" "$mismatch_start_time" 480 360 50 \
	>"$ROOT/tmp/scrcpy-wrapper-mismatch-wrapper.out" 2>&1
mismatch_status=$?
after_parent="$(parent_id "$child_id")"
if (( mismatch_status != 0 )) && [[ "$before_parent" == "$after_parent" ]] \
		&& kill -0 "$mismatch_pid" 2>/dev/null; then
	pass "wrapper rejects a window that does not belong to the supplied PID"
else
	fail "PID/window binding failed (status=$mismatch_status, parent $before_parent -> $after_parent)"
fi
kill -TERM "$mismatch_pid" 2>/dev/null || true
wait "$mismatch_pid" 2>/dev/null || true
mismatch_pid=""
kill -TERM "$fake_pid" 2>/dev/null || true
wait "$fake_pid" 2>/dev/null || true
fake_pid=""

# The supplied process identity must match the selected scrcpy process.
"$FAKE" >"$ROOT/tmp/scrcpy-wrapper-wrong-start-fake.out" 2>&1 &
fake_pid=$!
for _ in $(seq 1 50); do
	[[ -s "$ROOT/tmp/scrcpy-wrapper-wrong-start-fake.out" ]] && break
	sleep 0.05
done
child_id="$(awk '{print $2}' "$ROOT/tmp/scrcpy-wrapper-wrong-start-fake.out" \
	| sed 's/window=//')"
fake_start_time="$(process_start_time "$fake_pid")"
wrong_start_time="$((fake_start_time + 1))"
before_parent="$(parent_id "$child_id")"
"$WRAPPER" "$child_id" "$fake_pid" "$wrong_start_time" 480 360 50 \
	>"$ROOT/tmp/scrcpy-wrapper-wrong-start-wrapper.out" 2>&1
wrong_start_status=$?
after_parent="$(parent_id "$child_id")"
if (( wrong_start_status != 0 )) \
		&& [[ "$before_parent" == "$after_parent" ]] \
		&& kill -0 "$fake_pid" 2>/dev/null; then
	pass "wrapper rejects a mismatched scrcpy process start time"
else
	fail "process identity binding failed (status=$wrong_start_status)"
fi
kill -TERM "$fake_pid" 2>/dev/null || true
wait "$fake_pid" 2>/dev/null || true
fake_pid=""

# An out-of-band wrapper destruction must fail and terminate scrcpy.
if start_launcher; then
	xdotool windowkill "$wrapper_id"
	if wait_for_exit "$launcher_pid"; then
		wait "$launcher_pid"
		status=$?
		if (( status != 0 )) && ! kill -0 "$wrapper_pid" 2>/dev/null \
				&& ! kill -0 "$fake_pid" 2>/dev/null; then
			pass "abnormal wrapper destruction fails and closes both children"
		else
			fail "abnormal wrapper destruction returned status $status"
		fi
	else
		fail "launcher remained alive after abnormal wrapper destruction"
	fi
	launcher_pid=""
	wrapper_pid=""
	fake_pid=""
else
	fail "could not start launcher for abnormal-destruction test"
fi

# Direct wrapper use must report a monitored scrcpy failure as nonzero.
"$FAKE" >"$ROOT/tmp/scrcpy-wrapper-direct-crash-fake.out" 2>&1 &
fake_pid=$!
for _ in $(seq 1 50); do
	[[ -s "$ROOT/tmp/scrcpy-wrapper-direct-crash-fake.out" ]] && break
	sleep 0.05
done
child_id="$(awk '{print $2}' "$ROOT/tmp/scrcpy-wrapper-direct-crash-fake.out" \
	| sed 's/window=//')"
fake_start_time="$(process_start_time "$fake_pid")"
"$WRAPPER" "$child_id" "$fake_pid" "$fake_start_time" 480 360 50 \
	>"$ROOT/tmp/scrcpy-wrapper-direct-crash-wrapper.out" 2>&1 &
wrapper_pid=$!
sleep 0.3
kill -KILL "$fake_pid"
if wait_for_exit "$wrapper_pid"; then
	wait "$wrapper_pid" 2>/dev/null
	status=$?
	if (( status != 0 )); then
		pass "direct wrapper reports a monitored scrcpy crash as nonzero"
	else
		fail "direct wrapper returned status $status for a scrcpy crash"
	fi
else
	fail "direct wrapper remained alive after its scrcpy process crashed"
fi
wait "$fake_pid" 2>/dev/null || true
wrapper_pid=""
fake_pid=""

# Killing the launcher during window selection must not orphan scrcpy.
FAKE_SCRCPY_DELAY=5 SCRCPY_BIN="$FAKE" "$SCRIPT" \
	>"$ROOT/tmp/scrcpy-wrapper-launcher-kill.out" 2>&1 &
launcher_pid=$!
fake_pid=""
for _ in $(seq 1 50); do
	fake_pid="$(child_pid_by_executable "$launcher_pid" "$FAKE" || true)"
	[[ -n "$fake_pid" ]] && break
	sleep 0.05
done
if [[ -n "$fake_pid" ]]; then
	kill -KILL "$launcher_pid"
	if wait_for_exit "$fake_pid" 100; then
		pass "launcher watchdog stops scrcpy during window selection"
	else
		fail "scrcpy was orphaned when the launcher was killed"
	fi
else
	fail "could not start delayed scrcpy for launcher-watchdog test"
fi
launcher_pid=""
fake_pid=""

# A direct wrapper exit stops the monitored child.
"$FAKE" >"$ROOT/tmp/scrcpy-wrapper-teardown-fake.out" 2>&1 &
fake_pid=$!
for _ in $(seq 1 50); do
	[[ -s "$ROOT/tmp/scrcpy-wrapper-teardown-fake.out" ]] && break
	sleep 0.05
done
child_id="$(awk '{print $2}' "$ROOT/tmp/scrcpy-wrapper-teardown-fake.out" \
	| sed 's/window=//')"
fake_start_time="$(process_start_time "$fake_pid")"
"$WRAPPER" "$child_id" "$fake_pid" "$fake_start_time" 480 360 50 \
	>"$ROOT/tmp/scrcpy-wrapper-teardown-wrapper.out" 2>&1 &
wrapper_pid=$!
sleep 0.3
kill -TERM "$wrapper_pid"
wait "$wrapper_pid" 2>/dev/null
wrapper_status=$?
if wait_for_exit "$fake_pid" 50; then
	wait "$fake_pid" 2>/dev/null || true
	if [[ "$wrapper_status" == 143 ]] \
			&& ! xwininfo -id "$child_id" >/dev/null 2>&1; then
		pass "direct wrapper exit stops the monitored child"
	else
		fail "direct wrapper teardown differed (status=$wrapper_status)"
	fi
else
	fail "child process remained after the direct wrapper exited"
fi
kill -TERM "$fake_pid" 2>/dev/null || true
wait "$fake_pid" 2>/dev/null || true
fake_pid=""
wrapper_pid=""

# Cleanup keeps the child hidden while a stubborn scrcpy is being terminated.
FAKE_SCRCPY_IGNORE_TERM=1 "$FAKE" \
	>"$ROOT/tmp/scrcpy-wrapper-cleanup-fake.out" 2>&1 &
fake_pid=$!
for _ in $(seq 1 50); do
	[[ -s "$ROOT/tmp/scrcpy-wrapper-cleanup-fake.out" ]] && break
	sleep 0.05
done
child_id="$(awk '{print $2}' "$ROOT/tmp/scrcpy-wrapper-cleanup-fake.out" \
	| sed 's/window=//')"
fake_start_time="$(process_start_time "$fake_pid")"
"$WRAPPER" "$child_id" "$fake_pid" "$fake_start_time" 480 360 50 \
	>"$ROOT/tmp/scrcpy-wrapper-cleanup-wrapper.out" 2>&1 &
wrapper_pid=$!
for _ in $(seq 1 100); do
	wrapper_id="$(xdotool search --all --pid "$wrapper_pid" \
		--class '^X11ScrcpyWrapper$' 2>/dev/null | head -1)"
	[[ -n "$wrapper_id" ]] && break
	sleep 0.05
done
sleep 0.3
kill -TERM "$wrapper_pid"
sleep 0.5
if kill -0 "$fake_pid" 2>/dev/null && [[ "$(map_state "$child_id")" == "IsUnMapped" ]]; then
	pass "cleanup keeps the child hidden while scrcpy is stopping"
else
	fail "child was visible during cleanup"
fi
if wait_for_exit "$wrapper_pid" 50; then
	wait "$wrapper_pid" 2>/dev/null || true
else
	fail "wrapper did not finish terminating stubborn scrcpy"
fi
if ! kill -0 "$fake_pid" 2>/dev/null; then
	pass "stubborn scrcpy is terminated during cleanup"
else
	fail "stubborn scrcpy survived wrapper cleanup"
fi
kill -KILL "$fake_pid" 2>/dev/null || true
wait "$fake_pid" 2>/dev/null || true
fake_pid=""
wrapper_pid=""

# Invalid dimensions and incompatible scrcpy options must fail before launch.
for value in 0 319 16385 invalid; do
	if SCRCPY_SCROLL_WIDTH="$value" SCRCPY_BIN="$FAKE" "$SCRIPT" \
			>"$ROOT/tmp/scrcpy-wrapper-invalid.out" 2>&1; then
		fail "invalid width $value was accepted"
	else
		pass "invalid width $value is rejected"
	fi
done
for option in --fullscreen --flex-display --new-display --no-window \
		--max-size=800 --render-fit=letterbox --mouse=disabled -f -m -x; do
	if SCRCPY_BIN="$FAKE" "$SCRIPT" "$option" \
			>"$ROOT/tmp/scrcpy-wrapper-invalid.out" 2>&1; then
		fail "incompatible option $option was accepted"
	else
		pass "incompatible option $option is rejected"
	fi
done
if SCRCPY_BIN="$FAKE" "$SCRIPT" --mouse disabled \
		>"$ROOT/tmp/scrcpy-wrapper-invalid.out" 2>&1; then
	fail "separate --mouse disabled was accepted"
else
	pass "separate --mouse disabled is rejected"
fi

if pgrep -f "^$WRAPPER " >/dev/null || pgrep -x scrcpy-watch >/dev/null \
		|| pgrep -x fake-scrcpy-bin >/dev/null \
		|| pgrep -f "^$BUILD_DIR/" >/dev/null; then
	fail "synthetic scrcpy/wrapper processes remain after the test suite"
else
	pass "no synthetic scrcpy/wrapper processes remain"
fi

if (( failures > 0 )); then
	log "$failures test(s) failed"
	exit 1
fi

log "all synthetic wrapper tests passed"
