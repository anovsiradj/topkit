#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARIANT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$(cd "$VARIANT_DIR/../.." && pwd)"
BUILD_DIR="$(mktemp -d "$PROJECT_DIR/tmp/gtk-scrcpy-tests.XXXXXX")"
LOG_FILE="$PROJECT_DIR/tmp/gtk-scrcpy-wrapper-tests.out"
LAUNCHER="$VARIANT_DIR/gtk-scrcpy-wrapper.sh"
SOURCE="$VARIANT_DIR/gtk-scrcpy-wrapper.c"
WRAPPER_BINARY="$PROJECT_DIR/tmp/gtk-scrcpy-wrapper"
FAKE_BINARY="$BUILD_DIR/fake-scrcpy"
SEND_WM_DELETE_BINARY="$BUILD_DIR/send-wm-delete"
REPARENT_BINARY="$BUILD_DIR/reparent-window"
XVFB_BIN="${XVFB_BIN:-Xvfb}"
DISPLAY_NUM="${GTK_TEST_DISPLAY_NUM:-121}"
TEST_DISPLAY="127.0.0.1:${DISPLAY_NUM}"

FAILURES=0
XVFB_PID=""
LAUNCHER_PID=""
WRAPPER_PID=""
FAKE_PID=""
WATCHDOG_PID=""
UNRELATED_PID=""
LAUNCHER_LOG=""
DIRECT_FAKE_LOG=""
DIRECT_WRAPPER_LOG=""
CREATED_PIDS=()

cleanup() {
	local pid

	trap - EXIT
	for pid in "${LAUNCHER_PID:-}" "${WRAPPER_PID:-}" "${FAKE_PID:-}" \
			"${WATCHDOG_PID:-}" "${UNRELATED_PID:-}"; do
		if [[ -n "$pid" ]] && process_is_running "$pid"; then
			kill -TERM "$pid" 2>/dev/null || true
		fi
	done
	for pid in "${LAUNCHER_PID:-}" "${WRAPPER_PID:-}" "${FAKE_PID:-}" \
			"${WATCHDOG_PID:-}" "${UNRELATED_PID:-}"; do
		if [[ -n "$pid" ]]; then
			wait "$pid" 2>/dev/null || true
		fi
	done
	if [[ -n "$XVFB_PID" ]]; then
		kill -TERM "$XVFB_PID" 2>/dev/null || true
		wait "$XVFB_PID" 2>/dev/null || true
	fi
}

trap cleanup EXIT

fail_test() {
	printf 'FAIL: %s\n' "$*" | tee -a "$LOG_FILE"
	FAILURES=$((FAILURES + 1))
}

pass_test() {
	printf 'PASS: %s\n' "$*" | tee -a "$LOG_FILE"
}

assert_equal() {
	local expected="$1"
	local actual="$2"
	local name="$3"

	if [[ "$expected" == "$actual" ]]; then
		pass_test "$name"
	else
		fail_test "$name (expected '$expected', got '$actual')"
	fi
}

assert_nonzero() {
	local actual="$1"
	local name="$2"

	if [[ "$actual" != 0 ]]; then
		pass_test "$name"
	else
		fail_test "$name (expected a nonzero status)"
	fi
}

process_is_running() {
	local pid="$1"
	local state

	[[ -n "$pid" && -r "/proc/$pid/stat" ]] || return 1
	state="$(awk '{print $3}' "/proc/$pid/stat" 2>/dev/null || true)"
	[[ -n "$state" && "$state" != "Z" && "$state" != "X" ]]
}

wait_for_exit() {
	local pid="$1"
	local attempts="${2:-100}"
	local attempt

	for ((attempt = 0; attempt < attempts; attempt++)); do
		if ! process_is_running "$pid"; then
			wait "$pid" 2>/dev/null
			return $?
		fi
		sleep 0.1
	done
	return 124
}

wait_for_log() {
	local file="$1"
	local pattern="$2"
	local attempts="${3:-100}"
	local attempt

	for ((attempt = 0; attempt < attempts; attempt++)); do
		if grep -q "$pattern" "$file" 2>/dev/null; then
			return 0
		fi
		sleep 0.1
	done
	return 1
}

find_wrapper_pid() {
	local launcher_pid="$1"
	local pid
	local arguments

	while read -r pid arguments; do
		[[ -n "$pid" ]] || continue
		[[ "$arguments" == *"$WRAPPER_BINARY"* ]] || continue
		[[ "$arguments" == *"--watch-parent"* ]] && continue
		printf '%s\n' "$pid"
		return 0
	done < <(ps -o pid=,args= --ppid "$launcher_pid" 2>/dev/null)
	return 1
}

find_watchdog_pid() {
	local launcher_pid="$1"
	local pid
	local arguments

	while read -r pid arguments; do
		[[ -n "$pid" ]] || continue
		[[ "$arguments" == *"--watch-parent"* ]] || continue
		printf '%s\n' "$pid"
		return 0
	done < <(ps -o pid=,args= --ppid "$launcher_pid" 2>/dev/null)
	return 1
}

find_fake_pid() {
	local launcher_pid="$1"
	local pid
	local arguments

	while read -r pid arguments; do
		[[ -n "$pid" ]] || continue
		[[ "$arguments" == *"$FAKE_BINARY"* ]] || continue
		printf '%s\n' "$pid"
		return 0
	done < <(ps -o pid=,args= --ppid "$launcher_pid" 2>/dev/null)
	return 1
}

find_wrapper_window() {
	local wrapper_pid="$1"
	local window_id
	local protocols

	while read -r window_id; do
		[[ -n "$window_id" ]] || continue
		protocols="$(xprop -id "$window_id" WM_PROTOCOLS 2>/dev/null || true)"
		if [[ "$protocols" == *WM_DELETE_WINDOW* ]] \
				&& xwininfo -id "$window_id" 2>/dev/null \
					| grep -q 'Map State: IsViewable'; then
			printf '%s\n' "$window_id"
			return 0
		fi
	done < <(xdotool search --all --pid "$wrapper_pid" 2>/dev/null)
	return 1
}

absolute_x() {
	xwininfo -id "$1" 2>/dev/null \
		| awk '/Absolute upper-left X:/ { print $4; exit }'
}

absolute_y() {
	xwininfo -id "$1" 2>/dev/null \
		| awk '/Absolute upper-left Y:/ { print $4; exit }'
}

parent_window() {
	xwininfo -id "$1" -tree 2>/dev/null \
		| awk '/Parent window id:/ { print $4; exit }'
}

root_window() {
	xwininfo -root 2>/dev/null \
		| awk '/Window id:/ { print $4; exit }'
}

start_launcher() {
	local name="$1"
	shift

	LAUNCHER_LOG="$BUILD_DIR/${name}.launcher.out"
	: > "$LAUNCHER_LOG"
	DISPLAY="$TEST_DISPLAY" \
		SCRCPY_BIN="$FAKE_BINARY" \
		SCRCPY_SCROLL_WIDTH=640 \
		SCRCPY_SCROLL_HEIGHT=480 \
		SCRCPY_SCROLL_STEP=50 \
		env "$@" "$LAUNCHER" > "$LAUNCHER_LOG" 2>&1 &
	LAUNCHER_PID=$!
	CREATED_PIDS+=("$LAUNCHER_PID")
	if ! wait_for_log "$LAUNCHER_LOG" 'wrapped window' 150; then
		fail_test "$name launcher reached the embedded state"
		return 1
	fi

	FAKE_PID="$(sed -n 's/.*fake-scrcpy window=.* pid=\([0-9][0-9]*\).*/\1/p' \
		"$LAUNCHER_LOG" | head -n1)"
	WRAPPER_PID="$(find_wrapper_pid "$LAUNCHER_PID" || true)"
	WATCHDOG_PID="$(find_watchdog_pid "$LAUNCHER_PID" || true)"
	FOREIGN_ID="$(sed -n 's/.*fake-scrcpy window=\(0x[0-9a-fA-F]*\).*/\1/p' \
		"$LAUNCHER_LOG" | head -n1)"
	WRAPPER_WINDOW_ID="$(find_wrapper_window "$WRAPPER_PID" 2>/dev/null || true)"
	if [[ -z "$FAKE_PID" || -z "$WRAPPER_PID" || -z "$FOREIGN_ID" \
			|| -z "$WRAPPER_WINDOW_ID" ]]; then
		fail_test "$name launcher exposed its fake, wrapper, and windows"
		return 1
	fi
	CREATED_PIDS+=("$FAKE_PID" "$WRAPPER_PID")
	return 0
}

start_direct_fake() {
	DIRECT_FAKE_LOG="$BUILD_DIR/direct-fake.out"
	: > "$DIRECT_FAKE_LOG"
	DISPLAY="$TEST_DISPLAY" env "$@" "$FAKE_BINARY" > "$DIRECT_FAKE_LOG" 2>&1 &
	FAKE_PID=$!
	CREATED_PIDS+=("$FAKE_PID")
	if ! wait_for_log "$DIRECT_FAKE_LOG" 'fake-scrcpy window=' 50; then
		fail_test "direct fake created its window"
		return 1
	fi
	return 0
}

start_direct_wrapper() {
	local window_id="$1"
	local pid="$2"
	local start_time="$3"
	local width="$4"
	local height="$5"

	DIRECT_WRAPPER_LOG="$BUILD_DIR/direct-wrapper.out"
	: > "$DIRECT_WRAPPER_LOG"
	DISPLAY="$TEST_DISPLAY" "$WRAPPER_BINARY" "$window_id" "$pid" \
		"$start_time" "$width" "$height" 50 > "$DIRECT_WRAPPER_LOG" 2>&1 &
	WRAPPER_PID=$!
	CREATED_PIDS+=("$WRAPPER_PID")
	if ! wait_for_log "$DIRECT_WRAPPER_LOG" 'wrapped window' 80; then
		fail_test "direct wrapper reached the embedded state"
		return 1
	fi
	return 0
}

stop_scenario_processes() {
	local pid

	for pid in "${LAUNCHER_PID:-}" "${WRAPPER_PID:-}" "${FAKE_PID:-}" \
			"${WATCHDOG_PID:-}" "${UNRELATED_PID:-}"; do
		if [[ -n "$pid" ]] && process_is_running "$pid"; then
			kill -TERM "$pid" 2>/dev/null || true
		fi
	done
	for pid in "${LAUNCHER_PID:-}" "${WRAPPER_PID:-}" "${FAKE_PID:-}" \
			"${WATCHDOG_PID:-}" "${UNRELATED_PID:-}"; do
		if [[ -n "$pid" ]]; then
			wait "$pid" 2>/dev/null || true
		fi
	done
	LAUNCHER_PID=""
	WRAPPER_PID=""
	FAKE_PID=""
	WATCHDOG_PID=""
	UNRELATED_PID=""
}

mkdir -p "$PROJECT_DIR/tmp"
: > "$LOG_FILE"

for command in cc pkg-config xdotool xprop xwininfo ps sed awk grep env; do
	if ! command -v "$command" >/dev/null 2>&1; then
		printf 'Required command not found: %s\n' "$command" >&2
		exit 2
	fi
done
if ! command -v "$XVFB_BIN" >/dev/null 2>&1; then
	printf 'Required command not found: %s\n' "$XVFB_BIN" >&2
	exit 2
fi
if ! pkg-config --exists gtk+-3.0; then
	printf 'GTK3 development package not found: gtk+-3.0\n' >&2
	exit 2
fi

cc -std=c11 -O2 -Wall -Wextra -Wpedantic -o "$WRAPPER_BINARY" "$SOURCE" \
	$(pkg-config --cflags --libs gtk+-3.0) -lX11 -lXi || exit 1
cc -std=c11 -O2 -Wall -Wextra -Wpedantic -o "$FAKE_BINARY" \
	"$SCRIPT_DIR/helpers/fake-scrcpy.c" -lX11 || exit 1
cc -std=c11 -O2 -Wall -Wextra -Wpedantic -o "$SEND_WM_DELETE_BINARY" \
	"$SCRIPT_DIR/helpers/send-wm-delete.c" -lX11 || exit 1
cc -std=c11 -O2 -Wall -Wextra -Wpedantic -o "$REPARENT_BINARY" \
	"$SCRIPT_DIR/helpers/reparent-window.c" -lX11 || exit 1

"$XVFB_BIN" ":$DISPLAY_NUM" -screen 0 1280x2400x24 -nolisten unix \
	-listen tcp -pn > "$BUILD_DIR/xvfb.out" 2>&1 &
XVFB_PID=$!
for _ in $(seq 1 100); do
	if DISPLAY="$TEST_DISPLAY" xdpyinfo >/dev/null 2>&1; then
		break
	fi
	sleep 0.1
done
if ! DISPLAY="$TEST_DISPLAY" xdpyinfo >/dev/null 2>&1; then
	printf 'Could not start Xvfb: %s\n' "$XVFB_BIN" >&2
	exit 1
fi
export DISPLAY="$TEST_DISPLAY"

printf '%s\n' '== wheel, track paging, thumb drag, and WM close =='
if start_launcher basic; then
	root_id="$(root_window)"
	parent_id="$(parent_window "$FOREIGN_ID")"
	if [[ -n "$parent_id" && "$parent_id" != "$root_id" ]]; then
		pass_test "the scrcpy window is embedded below the GTK viewport"
	else
		fail_test "the scrcpy window is embedded below the GTK viewport"
	fi

	protocols="$(xprop -id "$WRAPPER_WINDOW_ID" WM_PROTOCOLS 2>/dev/null || true)"
	if [[ "$protocols" == *WM_DELETE_WINDOW* ]]; then
		pass_test "the GTK wrapper supports WM_DELETE_WINDOW"
	else
		fail_test "the GTK wrapper supports WM_DELETE_WINDOW"
	fi

	initial_x="$(absolute_x "$FOREIGN_ID")"
	initial_y="$(absolute_y "$FOREIGN_ID")"
	DISPLAY="$TEST_DISPLAY" xdotool mousemove --sync 100 100 click 5
	sleep 0.3
	assert_equal "$((initial_y - 50))" "$(absolute_y "$FOREIGN_ID")" "wheel down moves exactly 50 pixels"
	DISPLAY="$TEST_DISPLAY" xdotool click 4
	sleep 0.3
	assert_equal "$initial_y" "$(absolute_y "$FOREIGN_ID")" "wheel up restores the vertical position"

	DISPLAY="$TEST_DISPLAY" xdotool click 7
	sleep 0.3
	assert_equal "$((initial_x - 50))" "$(absolute_x "$FOREIGN_ID")" "horizontal wheel right moves exactly 50 pixels"
	DISPLAY="$TEST_DISPLAY" xdotool click 6
	sleep 0.3
	assert_equal "$initial_x" "$(absolute_x "$FOREIGN_ID")" "horizontal wheel left restores the horizontal position"

	before_bar_y="$(absolute_y "$FOREIGN_ID")"
	DISPLAY="$TEST_DISPLAY" xdotool mousemove --sync 637 100 click 5
	sleep 0.3
	assert_equal "$before_bar_y" "$(absolute_y "$FOREIGN_ID")" "wheel input over a scrollbar does not move the content"

	DISPLAY="$TEST_DISPLAY" xdotool mousemove --sync 637 250 click 1
	sleep 0.3
	track_y="$(absolute_y "$FOREIGN_ID")"
	if (( track_y < initial_y )); then
		pass_test "the vertical track pages toward the lower content"
	else
		fail_test "the vertical track pages toward the lower content"
	fi

	DISPLAY="$TEST_DISPLAY" xdotool mousemove --sync 550 472 click 1
	sleep 0.3
	track_x="$(absolute_x "$FOREIGN_ID")"
	if (( track_x < initial_x )); then
		pass_test "the horizontal track pages toward the right content"
	else
		fail_test "the horizontal track pages toward the right content"
	fi

	before_horizontal_drag_x="$(absolute_x "$FOREIGN_ID")"
	DISPLAY="$TEST_DISPLAY" xdotool mousemove --sync 500 472
	DISPLAY="$TEST_DISPLAY" xdotool mousedown 1
	sleep 0.1
	DISPLAY="$TEST_DISPLAY" xdotool mousemove --sync 300 472
	DISPLAY="$TEST_DISPLAY" xdotool mouseup 1
	sleep 0.4
	if (( $(absolute_x "$FOREIGN_ID") > before_horizontal_drag_x )); then
		pass_test "the horizontal scrollbar thumb is draggable"
	else
		fail_test "the horizontal scrollbar thumb is draggable"
	fi

	DISPLAY="$TEST_DISPLAY" "$SEND_WM_DELETE_BINARY" "$WRAPPER_WINDOW_ID"
	status=0
	wait "$LAUNCHER_PID" || status=$?
	assert_equal 0 "$status" "a normal WM close returns status 0"
	if ! process_is_running "$FAKE_PID"; then
		pass_test "a normal WM close terminates scrcpy"
	else
		fail_test "a normal WM close terminates scrcpy"
	fi
fi
stop_scenario_processes

printf '%s\n' '== overflow-only scrollbars, centering, and thumb dragging =='
if start_direct_fake; then
	direct_window_id="$(sed -n 's/.*fake-scrcpy window=\(0x[0-9a-fA-F]*\).*/\1/p' \
		"$DIRECT_FAKE_LOG" | head -n1)"
	direct_start_time="$(awk '{print $22}' "/proc/$FAKE_PID/stat")"
	if start_direct_wrapper "$direct_window_id" "$FAKE_PID" "$direct_start_time" 1000 800; then
		sleep 0.5
		one_axis_x="$(absolute_x "$direct_window_id")"
		one_axis_y="$(absolute_y "$direct_window_id")"
		if (( one_axis_x >= 60 && one_axis_x <= 90 && one_axis_y == 0 )); then
			pass_test "content that fits horizontally is centered without a horizontal scrollbar"
		else
			fail_test "content that fits horizontally is centered without a horizontal scrollbar"
		fi

		before_drag_y="$(absolute_y "$direct_window_id")"
		DISPLAY="$TEST_DISPLAY" xdotool mousemove --sync 992 10
		DISPLAY="$TEST_DISPLAY" xdotool mousedown 1
		sleep 0.1
		DISPLAY="$TEST_DISPLAY" xdotool mousemove --sync 992 300
		DISPLAY="$TEST_DISPLAY" xdotool mouseup 1
		sleep 0.4
		after_drag_y="$(absolute_y "$direct_window_id")"
		if (( after_drag_y < before_drag_y )); then
			pass_test "the vertical scrollbar thumb is draggable"
		else
			fail_test "the vertical scrollbar thumb is draggable"
		fi

		before_bottom_x="$(absolute_x "$direct_window_id")"
		DISPLAY="$TEST_DISPLAY" xdotool mousemove --sync 900 785 click 1
		sleep 0.3
		assert_equal "$before_bottom_x" "$(absolute_x "$direct_window_id")" "a hidden horizontal scrollbar does not page the content"

		before_track_y="$(absolute_y "$direct_window_id")"
		DISPLAY="$TEST_DISPLAY" xdotool mousemove --sync 992 740 click 1
		sleep 0.3
		if (( $(absolute_y "$direct_window_id") < before_track_y )); then
			pass_test "an overflowing vertical scrollbar remains interactive"
		else
			fail_test "an overflowing vertical scrollbar remains interactive"
		fi
	fi
fi
stop_scenario_processes

if start_direct_fake; then
	fit_window_id="$(sed -n 's/.*fake-scrcpy window=\(0x[0-9a-fA-F]*\).*/\1/p' \
		"$DIRECT_FAKE_LOG" | head -n1)"
	fit_start_time="$(awk '{print $22}' "/proc/$FAKE_PID/stat")"
	if start_direct_wrapper "$fit_window_id" "$FAKE_PID" "$fit_start_time" 1000 2100; then
		sleep 0.5
		assert_equal 84 "$(absolute_x "$fit_window_id")" "fully fitting content is centered horizontally"
		assert_equal 90 "$(absolute_y "$fit_window_id")" "fully fitting content is centered vertically"
		before_fit_x="$(absolute_x "$fit_window_id")"
		DISPLAY="$TEST_DISPLAY" xdotool mousemove --sync 500 2090 click 1
		sleep 0.3
		assert_equal "$before_fit_x" "$(absolute_x "$fit_window_id")" "fully fitting content has no active scrollbar track"
	fi
fi
stop_scenario_processes

printf '%s\n' '== scrcpy exit status propagation =='
if start_launcher normal-exit FAKE_SCRCPY_EXIT_AFTER=3 FAKE_SCRCPY_EXIT_STATUS=0; then
	status=0
	wait "$LAUNCHER_PID" || status=$?
	assert_equal 0 "$status" "a normal scrcpy exit is propagated"
fi
stop_scenario_processes

if start_launcher crash-exit FAKE_SCRCPY_EXIT_AFTER=3 FAKE_SCRCPY_EXIT_STATUS=137; then
	status=0
	wait "$LAUNCHER_PID" || status=$?
	assert_equal 137 "$status" "a scrcpy crash status is propagated"
fi
stop_scenario_processes

if start_direct_fake FAKE_SCRCPY_EXIT_AFTER=10 FAKE_SCRCPY_EXIT_STATUS=0; then
	sentinel_window_id="$(sed -n 's/.*fake-scrcpy window=\(0x[0-9a-fA-F]*\).*/\1/p' \
		"$DIRECT_FAKE_LOG" | head -n1)"
	sentinel_start_time="$(awk '{print $22}' "/proc/$FAKE_PID/stat")"
	DIRECT_WRAPPER_LOG="$BUILD_DIR/sentinel-wrapper.out"
	: > "$DIRECT_WRAPPER_LOG"
	DISPLAY="$TEST_DISPLAY" "$WRAPPER_BINARY" "$sentinel_window_id" \
		"$FAKE_PID" "$sentinel_start_time" 640 480 50 \
		> "$DIRECT_WRAPPER_LOG" 2>&1 &
	WRAPPER_PID=$!
	CREATED_PIDS+=("$WRAPPER_PID")
	status=0
	wait "$WRAPPER_PID" || status=$?
	assert_equal 125 "$status" "the direct wrapper reports an observed scrcpy exit with status 125"
fi
stop_scenario_processes

printf '%s\n' '== external reparent failure =='
if start_launcher reparent; then
	DISPLAY="$TEST_DISPLAY" "$REPARENT_BINARY" "$FOREIGN_ID"
	status=0
	wait "$LAUNCHER_PID" || status=$?
	assert_nonzero "$status" "an externally reparented target fails the wrapper"
	if ! process_is_running "$FAKE_PID"; then
		pass_test "an externally reparented target terminates scrcpy"
	else
		fail_test "an externally reparented target terminates scrcpy"
	fi
fi
stop_scenario_processes

printf '%s\n' '== process identity validation =='
if start_direct_fake; then
	identity_window_id="$(sed -n 's/.*fake-scrcpy window=\(0x[0-9a-fA-F]*\).*/\1/p' \
		"$DIRECT_FAKE_LOG" | head -n1)"
	sleep 30 &
	UNRELATED_PID=$!
	CREATED_PIDS+=("$UNRELATED_PID")
	unrelated_start_time="$(awk '{print $22}' "/proc/$UNRELATED_PID/stat")"
	DISPLAY="$TEST_DISPLAY" "$WRAPPER_BINARY" "$identity_window_id" \
		"$UNRELATED_PID" "$unrelated_start_time" 640 480 50 \
		> "$BUILD_DIR/pid-mismatch.out" 2>&1 &
	WRAPPER_PID=$!
	status=0
	wait "$WRAPPER_PID" || status=$?
	assert_nonzero "$status" "a target owned by another PID is rejected"
	if process_is_running "$FAKE_PID" && process_is_running "$UNRELATED_PID"; then
		pass_test "a PID mismatch does not terminate either unrelated process"
	else
		fail_test "a PID mismatch does not terminate either unrelated process"
	fi
fi
stop_scenario_processes

if start_direct_fake; then
	identity_window_id="$(sed -n 's/.*fake-scrcpy window=\(0x[0-9a-fA-F]*\).*/\1/p' \
		"$DIRECT_FAKE_LOG" | head -n1)"
	DISPLAY="$TEST_DISPLAY" "$WRAPPER_BINARY" "$identity_window_id" \
		"$FAKE_PID" 1 640 480 50 > "$BUILD_DIR/start-mismatch.out" 2>&1 &
	WRAPPER_PID=$!
	status=0
	wait "$WRAPPER_PID" || status=$?
	assert_nonzero "$status" "a mismatched process start time is rejected"
	if process_is_running "$FAKE_PID"; then
		pass_test "a start-time mismatch does not terminate the target"
	else
		fail_test "a start-time mismatch does not terminate the target"
	fi
fi
stop_scenario_processes

printf '%s\n' '== direct wrapper signal cleanup =='
if start_direct_fake; then
	direct_window_id="$(sed -n 's/.*fake-scrcpy window=\(0x[0-9a-fA-F]*\).*/\1/p' \
		"$DIRECT_FAKE_LOG" | head -n1)"
	direct_start_time="$(awk '{print $22}' "/proc/$FAKE_PID/stat")"
	if start_direct_wrapper "$direct_window_id" "$FAKE_PID" "$direct_start_time" 640 480; then
		kill -TERM "$WRAPPER_PID"
		status=0
		wait "$WRAPPER_PID" || status=$?
		assert_equal 143 "$status" "a terminated direct wrapper returns 128 plus SIGTERM"
		if ! process_is_running "$FAKE_PID"; then
			pass_test "a terminated direct wrapper stops its exact scrcpy process"
		else
			fail_test "a terminated direct wrapper stops its exact scrcpy process"
		fi
	fi
fi
stop_scenario_processes

printf '%s\n' '== launcher signal cleanup =='
if start_launcher launcher-signal; then
	kill -TERM "$LAUNCHER_PID"
	status=0
	wait "$LAUNCHER_PID" || status=$?
	assert_equal 143 "$status" "a terminated launcher returns 128 plus SIGTERM"
	if ! process_is_running "$FAKE_PID"; then
		pass_test "a terminated launcher stops scrcpy"
	else
		fail_test "a terminated launcher stops scrcpy"
	fi
fi
stop_scenario_processes

printf '%s\n' '== launcher death during window selection =='
LAUNCHER_LOG="$BUILD_DIR/launcher-death.launcher.out"
: > "$LAUNCHER_LOG"
DISPLAY="$TEST_DISPLAY" \
	SCRCPY_BIN="$FAKE_BINARY" \
	FAKE_SCRCPY_DELAY=2 \
	"$LAUNCHER" > "$LAUNCHER_LOG" 2>&1 &
LAUNCHER_PID=$!
CREATED_PIDS+=("$LAUNCHER_PID")
sleep 0.3
FAKE_PID="$(find_fake_pid "$LAUNCHER_PID" || true)"
WATCHDOG_PID="$(find_watchdog_pid "$LAUNCHER_PID" || true)"
if [[ -n "$FAKE_PID" && -n "$WATCHDOG_PID" ]]; then
	kill -KILL "$LAUNCHER_PID"
	wait "$LAUNCHER_PID" 2>/dev/null || true
	fake_status=0
	wait_for_exit "$FAKE_PID" 80 || fake_status=$?
	if ! process_is_running "$FAKE_PID"; then
		pass_test "killing the launcher during selection does not orphan scrcpy"
	else
		fail_test "killing the launcher during selection does not orphan scrcpy"
	fi
	watchdog_status=0
	wait_for_exit "$WATCHDOG_PID" 30 || watchdog_status=$?
	if ! process_is_running "$WATCHDOG_PID"; then
		pass_test "the parent-death watchdog exits after cleaning up scrcpy"
	else
		fail_test "the parent-death watchdog exits after cleaning up scrcpy"
	fi
else
	fail_test "the launcher starts its watchdog before window selection"
fi
stop_scenario_processes

printf '%s\n' '== argument validation =='
DISPLAY="$TEST_DISPLAY" SCRCPY_BIN="$FAKE_BINARY" \
	SCRCPY_SCROLL_WIDTH=1 "$LAUNCHER" > "$BUILD_DIR/invalid-width.out" 2>&1
status=$?
assert_equal 2 "$status" "an invalid wrapper width is rejected"
DISPLAY="$TEST_DISPLAY" SCRCPY_BIN="$FAKE_BINARY" \
	"$LAUNCHER" --fullscreen > "$BUILD_DIR/invalid-option.out" 2>&1
status=$?
assert_equal 2 "$status" "an incompatible scrcpy option is rejected"

printf '%s\n' '== leftover process check =='
leftover=0
for pid in "${CREATED_PIDS[@]}"; do
	if process_is_running "$pid"; then
		leftover=1
		fail_test "synthetic process $pid exited"
	fi
done
if (( leftover == 0 )); then
	pass_test "all synthetic processes exited"
fi

if (( FAILURES == 0 )); then
	printf 'All GTK scrcpy wrapper tests passed.\n' | tee -a "$LOG_FILE"
	exit 0
fi

printf '%d GTK scrcpy wrapper test(s) failed.\n' "$FAILURES" | tee -a "$LOG_FILE"
exit 1
