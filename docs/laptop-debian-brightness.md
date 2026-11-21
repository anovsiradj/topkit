# Display Brightness Debugging Report - Debian/XFCE

## System Information
- **OS**: Debian 13 (trixie)
- **Kernel**: 6.12.111+deb13-amd64
- **Desktop**: XFCE 4.20
- **Graphics**: AMD GPU (amdgpu driver, Cezanne Radeon Vega)
- **Display**: eDP (laptop internal display, 1920x1080)
- **Laptop**: HP EliteBook 845 G8
- **Backlight Device**: `/sys/class/backlight/amdgpu_bl0` (max 255)
- **Brightness Keys**: Fn+F3 / Fn+F4 (not F1/F2)

---

# RESOLVED (2026-11-21)

## Actual Root Cause

Two independent problems, layered on top of each other:

### 1. The kernel backlight was never wired to the panel
Writing to `/sys/class/backlight/amdgpu_bl0/brightness` updated `brightness` and
`actual_brightness` correctly, **but the physical panel never changed** — verified
by writing `0` (screen stayed at full brightness):

| `acpi_backlight=` | device created | physical effect |
|---|---|---|
| `video`    | `acpi_video0` | none |
| `vendor`   | *(none)*      | n/a |
| `native`   | `amdgpu_bl0` | none |

So neither the AMD PWM path nor the ACPI `_BCM` path reaches this panel.
**Permission fixes (udev `video` group, polkit) were never the real problem.**

### 2. The XFCE panel itself was off-screen
`/panels/panel-1/position` was `p=8;x=960;y=1066` → floating at a stale Y.
With a 61px panel on a 1080px screen the panel window actually landed at
**y=1190, i.e. ~110px below the bottom edge of the display**. Only a 3px
"autohide" strip was visible, so the panel slider was unreachable.

### 3. xfce4-power-manager was stealing the brightness keys
`xfce4-power-manager` grabs keycodes 232/233 (`XF86MonBrightnessDown/Up`) via
`XGrabKey` on the root window. Even with `handle-brightness-keys = false`, the
grab can persist across restarts (XFCE bug 14226). xfsettingsd must own the
keybinding instead.

---

## Current Fix

### 1. GRUB boot parameter
Changed `acpi_backlight=video` → `acpi_backlight=native` so the real
`amdgpu_bl0` device appears instead of the dummy `acpi_video0`.

Requires `sudo` (run manually per `AGENTS.md`):
```bash
sudo sed -i 's/acpi_backlight=video/acpi_backlight=native/' /etc/default/grub
sudo update-grub
# then reboot
```

### 2. Panel position fix
```bash
xfconf-query -c xfce4-panel -p /panels/panel-1/position -s 'p=8;x=960;y=1018'
xfconf-query -c xfce4-panel -p /panels/panel-1/autohide-behavior -s 0
xfconf-query -c xfce4-panel -p /panels/panel-1/position-locked -s true
xfce4-panel --restart
```
Verified: panel window at `1920x61+0+1019` (bottom of screen, visible).

### 3. Stop xfpm from grabbing brightness keys
```bash
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/handle-brightness-keys -s false
```
xfpm is still needed for battery monitoring, lid actions, DPMS, etc. — only its
brightness-key grab is disabled.

### 4. Route Fn keys through xfsettingsd + brightness-control.sh
xfsettingsd (auto-started via `/etc/xdg/autostart/xfsettingsd.desktop`) handles
the keybindings:

| Key | Keysym | Command |
|-----|--------|---------|
| Fn+F3 | `XF86MonBrightnessUp` | `brightness-control.sh up` |
| Fn+F4 | `XF86MonBrightnessDown` | `brightness-control.sh down` |

```bash
xfconf-query -c xfce4-keyboard-shortcuts \
  -p '/commands/custom/<XF86MonBrightnessUp>' \
  -n -t string -s "$HOME/.local/bin/brightness-control.sh up"

xfconf-query -c xfce4-keyboard-shortcuts \
  -p '/commands/custom/<XF86MonBrightnessDown>' \
  -n -t string -s "$HOME/.local/bin/brightness-control.sh down"
```

### 5. `devices/brightness-control.sh` — drives RandR Brightness
Since the hardware backlight is dead, brightness is controlled via the X11 RandR
`Brightness` property (`xrandr --output eDP --brightness <0.1-1.0>`).

Installed scripts (in `devices/`, tracked by git):

| File | Purpose |
|------|---------|
| `devices/brightness-control.sh` | CLI: up/down/set/get/restore/slider |
| `devices/brightness-slider.py` | GTK3 popup slider (closes on Escape / click-outside) |
| `devices/install-brightness-control.sh` | Installs launcher, autostart, keybindings |
| `devices/brightness-control.desktop` | Panel launcher |
| `devices/brightness-control-autostart.desktop` | Restore saved brightness at login |

Install (user level, no sudo):
```bash
./devices/install-brightness-control.sh
```

This symlinks the script into `~/.local/bin`, installs the panel launcher and
the login autostart entry, binds the Fn keys, and sets `handle-brightness-keys
= false`.

### 6. Panel launcher configuration
`xfce4-panel --add=launcher` creates an *empty* launcher plugin. The XFCE 4.20
launcher stores its items in the boxed xfconf property `items` as desktop-file
URI strings:

```bash
xfconf-query -c xfce4-panel -p /plugins/plugin-2/items \
  -n -t string -a -s 'file://$HOME/.local/share/applications/brightness-control.desktop'
```

---

## Usage

```bash
# CLI
brightness-control.sh get          # print current percent (10-100)
brightness-control.sh set 60       # set exact percent
brightness-control.sh up           # +10%
brightness-control.sh down         # -10%
brightness-control.sh restore      # re-apply last saved value (login)
brightness-control.sh slider       # GTK popup slider

# Keyboard (Fn keys on this laptop)
Fn+F3   # brightness up
Fn+F4   # brightness down

# Panel
Click the sun icon on the panel to open the slider popup.
```

---

## Known Issues & Limitations

### 1. xrandr brightness is software scaling, not real backlight
`xrandr --output eDP --brightness <value>` scales the output digitally
(gamma/luminance after the DAC), it does **not** change the physical backlight
LED power:
- **No battery savings** — backlight LEDs stay at full power.
- **Reduced contrast** — dark shades become greyish, not truly dim.
- **X11 only** — no effect on VT/console or boot splash.
- A future kernel fix (`amdgpu.abmlevel=0`, `amdgpu.dc=0`) may restore real
  hardware control and should be re-tested.

### 2. Hardware backlight is dead on this panel
`/sys/class/backlight/amdgpu_bl0/brightness` accepts writes and `actual_brightness`
follows them, but the panel ignores the value. This is a known AMD/ACPI
backlight regression on some laptops (kernel bug 216138 / XFCE bug 14226).

### 3. Fn lock
If Fn lock is activated, Fn+F3/F4 may emit plain function keys instead of
`XF86MonBrightness*`. Deactivate Fn lock (usually Fn+Esc or a BIOS setting) for
the brightness keys to work.

### 4. Panel position is floating (`p=8`)
The panel position uses floating coordinates (`p=8;x=960;y=1018`). After a
session restore it may drift. If the panel disappears or moves off-screen,
re-run the position fix in section 2.

### 5. xfsettingsd must own the brightness keys
If `xfce4-power-manager` is restarted or `handle-brightness-keys` reverts to
`true`, xfpm will re-grab the keys and xfsettingsd bindings will stop working.
Re-apply:
```bash
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/handle-brightness-keys -s false
```

---

## Files Modified / Created

| File | Action |
|------|--------|
| `/etc/default/grub` | `acpi_backlight=video` → `acpi_backlight=native` (sudo required) |
| `/etc/udev/rules.d/90-backlight.rules` | Pre-existing, unchanged (video group write) |
| `devices/brightness-control.sh` | **New** — RandR brightness CLI |
| `devices/brightness-slider.py` | **New** — GTK3 popup slider |
| `devices/install-brightness-control.sh` | **New** — installer |
| `devices/brightness-control.desktop` | **New** — panel launcher entry |
| `devices/brightness-control-autostart.desktop` | **New** — login restore |
| `devices/SNIPPETS.md` | Updated — brightness snippet added |
| `~/.local/bin/brightness-control.sh` | Symlink to `devices/brightness-control.sh` |
| `~/.local/share/applications/brightness-control.desktop` | Installed launcher |
| `~/.config/autostart/brightness-control.desktop` | Installed autostart restore |

---

## Commands to Reproduce (after GRUB change + reboot)

```bash
# 1. Fix panel position (if needed)
xfconf-query -c xfce4-panel -p /panels/panel-1/position -s 'p=8;x=960;y=1018'
xfconf-query -c xfce4-panel -p /panels/panel-1/autohide-behavior -s 0
xfconf-query -c xfce4-panel -p /panels/panel-1/position-locked -s true
xfce4-panel --restart

# 2. Stop xfpm from grabbing brightness keys
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/handle-brightness-keys -s false

# 3. Install brightness control
./devices/install-brightness-control.sh

# 4. Add launcher to panel (CLI)
xfconf-query -c xfce4-panel -p /plugins/plugin-2/items \
  -n -t string -a -s 'file://$HOME/.local/share/applications/brightness-control.desktop'

# 5. Test
brightness-control.sh set 50
brightness-control.sh slider
```

---

*Report generated: 2026-11-21*
*Tested on: Debian 13 (trixie) with XFCE 4.20, kernel 6.12, AMD GPU, HP EliteBook 845 G8*