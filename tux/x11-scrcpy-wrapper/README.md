# x11-scrcpy-wrapper

`x11-scrcpy-wrapper` runs scrcpy inside a normal, window-manager-managed X11 viewport. It reparents the actual scrcpy X11 window into the viewport, then clips and moves that window using the mouse wheel or embedded scrollbars. It does not modify scrcpy's canvas.

## Requirements

- Linux
- X11 with XInput2
- Bash 5.1 or newer
- C compiler (`cc` or `gcc`, configurable through `CC`)
- `scrcpy`
- `xdotool`, `xprop`, and `xwininfo`
- X11 and XInput2 development libraries (`libX11` and `libXi`)

## Usage

```bash
./tux/x11-scrcpy-wrapper/x11-scrcpy-wrapper.sh
```

The launcher rebuilds the helper binary automatically when the C source is newer.

The default viewport is `720x600`, and the initial scrcpy window height is `1920` pixels. These values can be overridden with environment variables:

```bash
SCRCPY_SCROLL_WIDTH=480 \
SCRCPY_SCROLL_HEIGHT=360 \
SCRCPY_SCROLL_STEP=50 \
SCRCPY_SCROLL_CHILD_HEIGHT=1920 \
SCRCPY_SCROLL_MAX_SIZE=1920 \
./tux/x11-scrcpy-wrapper/x11-scrcpy-wrapper.sh
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
./tux/x11-scrcpy-wrapper/x11-scrcpy-wrapper.sh --time-limit=60
```

## Scrolling

Move the pointer over the visible scrcpy content and use the mouse wheel:

| Wheel | Action |
|-------|--------|
| Up | Move the scrcpy window down, revealing content above |
| Down | Move the scrcpy window up, revealing content below |
| Left | Move the scrcpy window right, revealing content on the left |
| Right | Move the scrcpy window left, revealing content on the right |

The wrapper embeds browser-style scrollbars:

- A vertical track and draggable thumb appear on the right when the content is taller than the viewport.
- A horizontal track and draggable thumb appear at the bottom when the content is wider than the viewport.
- Dragging a thumb moves the scrcpy window.
- Clicking a track pages toward that end of the content.
- Scrollbar space is reserved from the content viewport, so it never covers the phone image.

Wheel buttons 4–7 are handled through XInput2. Scrcpy may also receive the original wheel event, so a wheel gesture can scroll the Android content as well as move the X11 scrcpy window.

## Window and process behavior

- The viewport is a normal top-level X11 window with standard window-manager decorations and controls.
- The launcher selects the stable, mapped scrcpy client associated with the launched process.
- Closing the viewport terminates scrcpy, and exiting scrcpy closes the viewport.
- The launcher cleans up both processes on exit and preserves scrcpy's exit status.

## Incompatible scrcpy options

The launcher rejects options that conflict with the managed X11 viewport:

- `--always-on-top`, `--fullscreen`, `--no-window`, `--v4l2-sink`, and `--otg`
- `--flex-display`/`-x` and `--new-display`
- `--max-size`, `--max-fps`, `--render-fit`, `--window-width`, `--window-height`, and `--window-title`
- `--no-playback`, `--no-video`, and `--no-video-playback`
- `--mouse disabled` and `--mouse=disabled`
- Information-only modes such as `--help`, `--version`, and `--list-*`

## Tests

The suite uses a synthetic X11 scrcpy client and does not launch real scrcpy or access an Android device.

```bash
./tux/x11-scrcpy-wrapper/tests/test-scrcpy-wrapper.sh
```

## Limitations

- The method relies on reparenting scrcpy's SDL window.
- Devices that emit high-resolution scroll valuators instead of wheel buttons 4–7 may not trigger viewport movement.
- If the mirrored window fits the viewport in a direction, there is nothing to reveal in that direction.

## Fallback

If the wrapper is not usable, run scrcpy directly and let it scale the complete canvas:

```bash
scrcpy --max-size=1920 --max-fps=60 --render-fit=letterbox
```
