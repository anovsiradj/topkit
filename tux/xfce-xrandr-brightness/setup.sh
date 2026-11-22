#!/bin/sh
#
# setup.sh
# Install the brightness slider for XFCE on the HP EliteBook 845 G8.
#
# What it does (all user level, no sudo):
#   1. Installs the panel launcher and the login autostart desktop entries
#   2. Binds XF86MonBrightnessUp / XF86MonBrightnessDown to the script
#   3. Stops xfce4-power-manager from grabbing those keys itself
#
# usage:
#   ./tux/xfce-xrandr-brightness/setup.sh            # install
#   ./tux/xfce-xrandr-brightness/setup.sh --uninstall  # remove everything
#
# After installing, add the launcher to the panel:
#   right click on the panel -> Add New Items -> Launcher -> pick "Brightness"

set -u

script_dir=$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)
script_path=$(readlink -f -- "$script_dir/brightness-control.sh")

apps_dir="$HOME/.local/share/applications"
autostart_dir="$HOME/.config/autostart"

launcher_entry="$apps_dir/xfce-xrandr-brightness.desktop"
autostart_entry="$autostart_dir/xfce-xrandr-brightness-autostart.desktop"

up_binding="/commands/custom/<XF86MonBrightnessUp>"
down_binding="/commands/custom/<XF86MonBrightnessDown>"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--uninstall]

  (no option)   install the brightness slider, launcher and key bindings
  --uninstall   remove the launcher, autostart entry and key bindings
EOF
}

uninstall() {
    rm -f "$launcher_entry"
    rm -f "$autostart_entry"
    xfconf-query -c xfce4-keyboard-shortcuts -p "$up_binding" -r 2>/dev/null
    xfconf-query -c xfce4-keyboard-shortcuts -p "$down_binding" -r 2>/dev/null
    xfconf-query -c xfce4-power-manager \
        -p /xfce4-power-manager/handle-brightness-keys -s true 2>/dev/null
    echo "brightness control removed"
}

install() {
    mkdir -p "$apps_dir" "$autostart_dir"

    chmod +x "$script_path" "$script_dir/brightness-slider.py"

    sed "s#__SCRIPT__#$script_path#g" "$script_dir/brightness-control.desktop" \
        > "$launcher_entry"
    sed "s#__SCRIPT__#$script_path#g" "$script_dir/brightness-autostart.desktop" \
        > "$autostart_entry"
    chmod +x "$launcher_entry" "$autostart_entry"

    # XFCE key bindings for the Fn brightness keys
    xfconf-query -c xfce4-keyboard-shortcuts -p "$up_binding" \
        -n -t string -s "$script_path up"
    xfconf-query -c xfce4-keyboard-shortcuts -p "$down_binding" \
        -n -t string -s "$script_path down"

    # xfce4-power-manager would grab the very same keys and drive the dead
    # hardware backlight, so let it go.
    xfconf-query -c xfce4-power-manager \
        -p /xfce4-power-manager/handle-brightness-keys -s false

    echo "installed:"
    echo "  script  : $script_path"
    echo "  launcher: $launcher_entry"
    echo "  autostart: $autostart_entry"
    echo
    echo "Add it to the panel: right click the panel -> Add New Items ->"
    echo "Launcher -> 'Brightness'. Then press the Fn brightness keys."
}

case "${1:-}" in
    --uninstall) uninstall ;;
    -h|--help) usage ;;
    "") install ;;
    *)
        usage >&2
        exit 1
        ;;
esac
