# gtk-scrcpy-wrapper

`gtk-scrcpy-wrapper` runs scrcpy inside a normal, window-manager-managed GTK3 X11 viewport. It embeds the actual scrcpy X11 window in a GTK `GtkSocket`, then clips and moves that window using the mouse wheel or native GTK scrollbars. It does not modify scrcpy's canvas.

## Requirements

- Linux
- X11 with XInput2
- Bash 5.1 or newer
- C compiler (`cc` or `gcc`, configurable through `CC`)
- `scrcpy`
- GTK3 and its development files (`gtk+-3.0`)
- `pkg-config`, `xdotool`, `xprop`, and `xwininfo`
- X11 and XInput2 development libraries (`libX11` and `libXi`)

## Usage

```bash
./tux/gtk-scrcpy-wrapper/gtk-scrcpy-wrapper.sh
```

The launcher rebuilds the helper binary automatically when the C source is newer.

The default viewport is `720x600`, and the initial scrcpy window height is `1920` pixels. These values can be overridden with environment variables:

```bash
SCRCPY_SCROLL_WIDTH=480 \
SCRCPY_SCROLL_HEIGHT=360 \
SCRCPY_SCROLL_STEP=50 \
SCRCPY_SCROLL_CHILD_HEIGHT=1920 \
SCRCPY_SCROLL_MAX_SIZE=1920 \
./tux/gtk-scrcpy-wrapper/gtk-scrcpy-wrapper.sh
```

| Variable | Meaning |
|----------|---------|
| `SCRCPY_SCROLL_WIDTH` | Viewport width in pixels (320–16384) |
| `SCRCPY_SCROLL_HEIGHT` | Viewport height in pixels (320–16384) |
| `SCRCPY_SCROLL_STEP` | Pixels moved per wheel event (1–1000) |
| `SCRCPY_SCROLL_CHILD_HEIGHT` | Initial scrcpy window height |
| `SCRCPY_SCROLL_MAX_SIZE` | Maximum encoded video size passed to scrcpy |
| `SCRCPY_BIN` | Alternative scrcpy executable |

Compatible scrcpy arguments can be appended to the command:

```bash
./tux/gtk-scrcpy-wrapper/gtk-scrcpy-wrapper.sh --time-limit=60
```

## Scrolling

Move the pointer over the visible scrcpy content and use the mouse wheel:

| Wheel | Action |
|-------|--------|
| Up | Move the scrcpy window down, revealing content above |
| Down | Move the scrcpy window up, revealing content below |
| Left | Move the scrcpy window right, revealing content on the left |
| Right | Move the scrcpy window left, revealing content on the right |

The wrapper uses native GTK scrollbars:

- A vertical track and draggable thumb appear on the right only when the content is taller than the viewport.
- A horizontal track and draggable thumb appear at the bottom only when the content is wider than the viewport.
- Dragging a thumb moves the scrcpy window.
- Clicking a track pages toward that end of the content.
- Scrollbar space is reserved from the content viewport, so it never covers the phone image.
- Content that fits is centered in the available viewport area.

Wheel buttons 4–7 are handled through XInput2. Scrcpy may also receive the original wheel event, so a wheel gesture can scroll the Android content as well as move the X11 scrcpy window.

## Window and process behavior

- The viewport is a normal GTK top-level X11 window with standard window-manager decorations and controls.
- The launcher selects the stable, mapped scrcpy client associated with the launched process.
- The helper verifies the target window's process ID, process start time, and optional pidfd before and after embedding it.
- Closing the viewport terminates scrcpy, and exiting scrcpy closes the viewport.
- The launcher cleans up both processes on exit and preserves scrcpy's exit status.

## Incompatible scrcpy options

The launcher rejects options that conflict with the managed GTK3 viewport:

- `--always-on-top`, `--fullscreen`, `--no-window`, `--v4l2-sink`, and `--otg`
- `--flex-display`/`-x` and `--new-display`
- `--max-size`, `--max-fps`, `--render-fit`, `--window-width`, `--window-height`, and `--window-title`
- `--no-playback`, `--no-video`, and `--no-video-playback`
- `--mouse disabled` and `--mouse=disabled`
- Information-only modes such as `--help`, `--version`, and `--list-*`

## Tests

The suite uses a synthetic X11 scrcpy client and does not launch real scrcpy or access an Android device. It requires `Xvfb`.

```bash
./tux/gtk-scrcpy-wrapper/tests/test-gtk-scrcpy-wrapper.sh
```

Set `XVFB_BIN` if `Xvfb` is not available as a command in `PATH`.

## Limitations

- The method relies on embedding scrcpy's SDL window with GTK3 `GtkSocket`.
- Devices that emit high-resolution scroll valuators instead of wheel buttons 4–7 may not trigger viewport movement.
- If the mirrored window fits the viewport in a direction, there is nothing to reveal in that direction.

## Fallback

If the wrapper is not usable, run scrcpy directly and let it scale the complete canvas:

```bash
scrcpy --max-size=1920 --max-fps=60 --render-fit=letterbox
```
