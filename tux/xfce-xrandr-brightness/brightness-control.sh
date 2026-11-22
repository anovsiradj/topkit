#!/bin/sh
#
# brightness-control.sh
# Screen brightness control for the HP EliteBook 845 G8 (Debian 13 / XFCE 4.20).
#
# WHY THIS IS NEEDD
# -----------------
# The kernel exposes backlight devices under /sys/class/backlight:
#   - acpi_video0  (when acpi_backlight=video)   -> values change, panel ignores them
#   - amdgpu_bl0   (when acpi_backlight=native)  -> values change, panel ignores them
# Writing 0 into amdgpu_bl0/brightness updates `brightness` and `actual_brightness`
# correctly, yet the eDP panel stays at full brightness (verified on this machine).
# The panel backlight is simply not reachable through the AMD/ACPI PWM path.
#
# The one interface that IS wired to the panel is the X11 RandR "Brightness"
# property (xrandr --output eDP --brightness), which scales the output. It is
# confirmed working and is what this script drives.
#
# usage:
#   ./tux/xfce-xrandr-brightness/brightness-control.sh up        # +10%
#   ./tux/xfce-xrandr-brightness/brightness-control.sh down      # -10%
#   ./tux/xfce-xrandr-brightness/brightness-control.sh set 60    # set exact percent (10-100)
#   ./tux/xfce-xrandr-brightness/brightness-control.sh get       # print current percent
#   ./tux/xfce-xrandr-brightness/brightness-control.sh restore   # re-apply the saved value
#   ./tux/xfce-xrandr-brightness/brightness-control.sh slider    # open the GTK slider popup
#
# The brightness keys on this laptop are Fn+F3/F4 (they emit the standard
# XF86MonBrightnessDown / XF86MonBrightnessUp key names, bound by
# tux/xfce-xrandr-brightness/setup.sh).
#
# install (user level, no sudo):
#   ./tux/xfce-xrandr-brightness/setup.sh
#
# files:
#   ~/.config/brightness-ctl/config    optional config, e.g. MODE=software
#   ~/.local/state/brightness-ctl/value  last used percent

set -u

MIN=10
MAX=100
STEP=10

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/brightness-ctl"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/brightness-ctl"
STATE_FILE="$STATE_DIR/value"
CONFIG_FILE="$CONFIG_DIR/config"

# resolve the script path so the slider script is found regardless of
# how this script is invoked
script_path=$(readlink -f -- "$0" 2>/dev/null || echo "$0")
script_dir=$(cd -- "$(dirname -- "$script_path")" >/dev/null 2>&1 && pwd)

mkdir -p "$STATE_DIR" "$CONFIG_DIR"

# MODE: software (default, xrandr) | hardware (sysfs only) | both
MODE="software"
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi
MODE="${MODE:-software}"

# ------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") [COMMAND]

Commands:
  up          increase brightness by $STEP%
  down        decrease brightness by $STEP%
  set N       set brightness to N% ($MIN-$MAX)
  get         print the current brightness in percent
  restore     re-apply the last saved brightness (used at login)
  slider      open the graphical slider popup

Current mode: $MODE
EOF
}

# ------------------------------------------------------------------
clamp() {
    value="$1"
    [ "$value" -lt "$MIN" ] && value=$MIN
    [ "$value" -gt "$MAX" ] && value=$MAX
    printf '%s' "$value"
}

# ------------------------------------------------------------------
# First connected output, e.g. eDP-1 / eDP
detect_output() {
    xrandr --query 2>/dev/null | awk '/ connected/ {print $1; exit}'
}

# ------------------------------------------------------------------
get_brightness() {
    value="$(xrandr --verbose 2>/dev/null | awk '/Brightness:/ {print $2; exit}')"
    [ -n "${value:-}" ] || value="1.0"
    awk -v v="$value" 'BEGIN {
        p = int(v * 100 + 0.5)
        if (p < 10) p = 10
        if (p > 100) p = 100
        print p
    }'
}

# ------------------------------------------------------------------
# Best effort hardware write. Kept for machines where the panel backlight
# does respond (MODE=hardware / MODE=both).
hw_set() {
    percent="$1"
    for device in /sys/class/backlight/*; do
        [ -w "$device/brightness" ] || continue
        maximum="$(cat "$device/max_brightness" 2>/dev/null || echo 255)"
        [ -n "$maximum" ] || maximum=255
        if echo $(( percent * maximum / 100 )) > "$device/brightness" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

# ------------------------------------------------------------------
set_brightness() {
    percent="$(clamp "$1")"
    fraction="$(awk -v p="$percent" 'BEGIN {printf "%.2f", p / 100}')"
    output="$(detect_output)"

    if [ -z "$output" ]; then
        echo "brightness-control: no connected display found" >&2
        return 1
    fi

    case "$MODE" in
        hardware|both) hw_set "$percent" ;;
    esac

    if [ "$MODE" != "hardware" ]; then
        xrandr --output "$output" --brightness "$fraction" || return 1
    fi

    printf '%s' "$percent" > "$STATE_FILE"
    echo "$percent"
}

# ------------------------------------------------------------------
case "${1:-}" in
    up)
        set_brightness $(( $(get_brightness) + STEP ))
        ;;
    down)
        set_brightness $(( $(get_brightness) - STEP ))
        ;;
    set)
        set_brightness "${2:-100}"
        ;;
    get)
        get_brightness
        ;;
    restore)
        if [ -f "$STATE_FILE" ]; then
            set_brightness "$(cat "$STATE_FILE")" >/dev/null
        else
            set_brightness 100 >/dev/null
        fi
        ;;
    slider)
        exec python3 "$script_dir/brightness-slider.py"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage >&2
        exit 1
        ;;
esac
