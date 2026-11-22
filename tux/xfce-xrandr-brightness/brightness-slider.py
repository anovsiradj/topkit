#!/usr/bin/env python3
"""
brightness-slider.py
Graphical brightness slider popup for XFCE.

Drives the X11 RandR "Brightness" property (xrandr --output <out> --brightness)
because the hardware backlight of this laptop (HP EliteBook 845 G8) accepts
sysfs values but does not change the panel.

Standalone usage:
    python3 tux/xfce-xrandr-brightness/brightness-slider.py
"""

import os
import subprocess
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

MIN = 10
MAX = 100
STEP = 5

STATE_DIR = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
    "brightness-ctl",
)
STATE_FILE = os.path.join(STATE_DIR, "value")

ICON_NAME = "display-brightness-symbolic"

# ---- Configurable constants (edit these to tweak appearance/behavior) ----
WINDOW_WIDTH = 320
WINDOW_HEIGHT = 74
SCALE_WIDTH = 220
LABEL_WIDTH = 44
BOX_SPACING = 8
BOX_BORDER_WIDTH = 8
SLIDER_BOTTOM_PCT = 0.02   # 2% of screen height
SLIDER_SIDE_PCT = 0.02     # 2% of screen width
# --------------------------------------------------------------------------


def which(program):
    """Minimal PATH lookup; shutil is avoided to keep the file dependency-free."""
    for path in os.environ.get("PATH", "").split(os.pathsep):
        candidate = os.path.join(path, program)
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return None


def detect_output():
    """Return the first connected X output name (e.g. eDP-1)."""
    try:
        listing = subprocess.check_output(["xrandr", "--query"], text=True)
    except (OSError, subprocess.CalledProcessError):
        return None
    for line in listing.splitlines():
        if " connected" in line:
            return line.split()[0]
    return None


def current_percent():
    """Read the current RandR brightness and convert it to a percent."""
    try:
        verbose = subprocess.check_output(["xrandr", "--verbose"], text=True)
    except (OSError, subprocess.CalledProcessError):
        return 100
    for line in verbose.splitlines():
        stripped = line.strip()
        if stripped.startswith("Brightness:"):
            try:
                value = float(stripped.split()[1])
            except (IndexError, ValueError):
                break
            percent = int(round(value * 100))
            return max(MIN, min(MAX, percent))
    return 100


def apply_percent(percent):
    """Set the RandR brightness and remember the value."""
    output = detect_output()
    if output is None:
        return
    fraction = percent / 100.0
    subprocess.run(
        ["xrandr", "--output", output, "--brightness", "{:.2f}".format(fraction)],
        check=False,
    )
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        with open(STATE_FILE, "w") as handle:
            handle.write(str(percent))
    except OSError:
        pass


class BrightnessWindow(Gtk.Window):
    """Small frameless popup holding the brightness scale.

    Why the extra focus work: with Gdk.WindowTypeHint.DOCK the popup never
    receives keyboard/mouse focus, so the Escape key and the click-to-dismiss
    gesture were ignored. The window therefore uses UTILITY + an explicit
    input grab, and closes on: Escape, focus-out, or a click on its background.
    """

    def __init__(self):
        super().__init__(title="Brightness")
        self.set_default_size(WINDOW_WIDTH, WINDOW_HEIGHT)
        self.set_resizable(False)
        self.set_decorated(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_keep_above(True)
        self.set_accept_focus(True)
        self.set_position(Gtk.WindowPosition.NONE)
        self.set_type_hint(Gdk.WindowTypeHint.UTILITY)

        # Escape/Return close the popup even while the scale holds focus.
        accelerators = Gtk.AccelGroup()
        accelerators.connect(
            Gdk.keyval_from_name("Escape"), 0, Gtk.AccelFlags.VISIBLE, self.on_close
        )
        accelerators.connect(
            Gdk.keyval_from_name("Return"), 0, Gtk.AccelFlags.VISIBLE, self.on_close
        )
        accelerators.connect(
            Gdk.keyval_from_name("KP_Enter"), 0, Gtk.AccelFlags.VISIBLE, self.on_close
        )
        self.add_accel_group(accelerators)

        self.connect("realize", self.on_realize)
        self.connect("show", self.on_show)
        self.connect("delete-event", self.on_delete)
        self.connect("key-press-event", self.on_key_press)
        self.connect("focus-out-event", self.on_focus_out)
        self.connect("button-press-event", self.on_button_press)

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=BOX_SPACING)
        box.set_border_width(BOX_BORDER_WIDTH)
        self.add(box)

        icon = Gtk.Image.new_from_icon_name(ICON_NAME, Gtk.IconSize.BUTTON)
        box.pack_start(icon, False, False, 0)

        self.scale = Gtk.Scale.new_with_range(
            Gtk.Orientation.HORIZONTAL, MIN, MAX, STEP
        )
        self.scale.set_draw_value(False)
        self.scale.set_size_request(SCALE_WIDTH, -1)
        self.scale.set_value(current_percent())
        self.scale.set_increments(STEP, STEP)
        self.scale.set_can_focus(True)
        self.scale.connect("value-changed", self.on_value_changed)
        self.scale.connect("key-press-event", self.on_key_press)
        box.pack_start(self.scale, True, True, 0)

        self.label = Gtk.Label(label="{}%".format(int(self.scale.get_value())))
        self.label.set_size_request(LABEL_WIDTH, -1)
        box.pack_start(self.label, False, False, 0)

    # ------------------------------------------------------------------
    def on_realize(self, *_args):
        gdk_window = self.get_window()
        if gdk_window is not None:
            gdk_window.set_accept_focus(True)

    def on_show(self, *_args):
        # The input grab is what makes a click outside the popup dismiss it.
        GLib.idle_add(self.install_grab)

    def install_grab(self):
        try:
            Gtk.grab_add(self)
        except Exception:  # pragma: no cover - defensive only
            pass
        self.grab_focus()
        self.scale.grab_focus()
        return False

    def on_delete(self, *_args):
        # The grab is removed automatically on destroy.
        return False

    # ------------------------------------------------------------------
    def on_close(self, *_args):
        self.destroy()
        return True

    def on_key_press(self, _widget, event):
        if event.keyval == Gdk.KEY_Escape:
            self.destroy()
            return True
        return False

    def on_focus_out(self, _widget, _event):
        self.destroy()
        return False

    def on_button_press(self, _widget, event):
        # Clicking anywhere that is not the scale dismisses the popup.
        coords = self.translate_coordinates(self.scale, int(event.x), int(event.y))
        if coords is None:
            self.destroy()
            return False
        x, y = coords
        allocation = self.scale.get_allocation()
        inside_scale = 0 <= x <= allocation.width and 0 <= y <= allocation.height
        if not inside_scale:
            self.destroy()
        return False

    def on_value_changed(self, widget):
        percent = int(widget.get_value())
        self.label.set_text("{}%".format(percent))
        apply_percent(percent)

    # ------------------------------------------------------------------
    def place_near_panel(self):
        """Put the popup just above the bottom panel, centered."""
        display = Gdk.Display.get_default()
        if display is None:
            return
        monitor = display.get_primary_monitor() or display.get_monitor(0)
        if monitor is None:
            return
        geometry = monitor.get_workarea()
        _, height = self.get_size()

        # Percentage-based margins relative to screen dimensions
        bottom_pct = 0.02   # 2% of screen height
        side_pct = 0.02     # 2% of screen width

        bottom_margin = int(geometry.height * bottom_pct)
        side_margin = int(geometry.width * side_pct)

        # Center horizontally, respecting side margin
        x = geometry.x + max(side_margin, (geometry.width - 320) // 2)
        y = geometry.y + geometry.height - height - bottom_margin

        self.move(x, y)
        self.present()


def main():
    if not which("xrandr"):
        print("brightness-slider: xrandr is required", file=sys.stderr)
        return 1

    window = BrightnessWindow()
    window.connect("destroy", Gtk.main_quit)
    window.show_all()
    window.place_near_panel()
    # keep the grab installed after present()
    GLib.idle_add(window.install_grab)
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())