# Hyprland wallpaper picker

A coverflow-style wallpaper picker for Hyprland, built with
[Quickshell](https://quickshell.org), [awww](https://codeberg.org/LGFae/awww)
and [mpvpaper](https://github.com/GhostNaN/mpvpaper).

It scans a folder, caches thumbnails, and opens as a full-screen layer-shell
overlay on the focused monitor. The desktop behind it is blurred by Hyprland,
not by the picker.

## Features

- Animated coverflow strip with keyboard, mouse and trackpad navigation.
- Optional looping (`strip.loopMode`): `endless` keeps the row continuous and
  repeats wallpapers when needed; `jump` wraps instantly between the ends
  without duplicates; `off` stops at the ends.
- Search by wallpaper name: jump to the best match while typing, or hide
  non-matching wallpapers (see `search.mode` in `Config.qml`).
- Only a window of tiles around the selection is instantiated, so large
  folders stay responsive.
- Thumbnail cache keyed by source path and generation options; changing the
  thumbnail size, mode or corner radius regenerates it automatically.
- The focused tile shows a wider, higher-resolution crop generated and cached
  during the scan, so it is available as soon as a wallpaper is focused.
- Thumbnails are generated with ImageMagick 7; files that cannot be converted
  are skipped and reported.
- Starts on the wallpaper that is currently displayed.
- GIFs are supported, and animated GIFs are also shown live on the desktop.
- Video wallpapers are played by [mpvpaper](https://github.com/GhostNaN/mpvpaper)
  and appear in the same strip as images.
- Short muted previews of videos and animated GIFs play in the focused tile.
  The clips are cached, so revisiting a wallpaper is instant.
- A `LIVE` badge marks wallpapers that animate on the desktop.
- The picker switches between awww and mpvpaper automatically.
- Applies wallpapers with configurable awww transitions.
- Shows scan, query and apply errors in the overlay instead of failing silently.
- Single-instance toggle through Quickshell IPC.

## Requirements

- Hyprland (layer-shell support)
- Quickshell (`qs`)
- awww, including `awww-daemon`
- mpvpaper (with its libmpv dependency), for video wallpapers
- ffmpeg with the WebP animation encoder, for video posters and live previews
- bash, coreutils, findutils, procps-ng and util-linux
- ImageMagick 7 (`magick`)

## Setup

1. Make sure the scripts are executable:

   ```sh
   chmod +x scripts/*.sh
   ```

2. Bind the toggle script in Hyprland. For `hyprland.conf`:

   ```ini
   bind = SUPER, W, exec, /path/to/hyprland-wallpaper-picker/scripts/open-picker.sh
   ```

   For the Lua configuration API:

   ```lua
   hl.bind("SUPER + W", hl.dsp.exec_cmd("/path/to/hyprland-wallpaper-picker/scripts/open-picker.sh"))
   ```

3. Optional: blur the desktop behind the picker:

   ```ini
   layerrule = blur, quickshell:wallpaperPicker
   ```

   ```lua
   hl.layer_rule({ match = { namespace = "quickshell:wallpaperPicker" }, blur = true })
   ```

   The namespace is set in `WallpaperPicker.qml`; if you change it, update the
   layer rule to match.

The toggle script starts `awww-daemon` if it is not already running. Running
the picker directly also works:

```sh
qs -p /path/to/hyprland-wallpaper-picker
```

## Usage

| Input | Action |
| --- | --- |
| `Left` / `Right` | Move the selection |
| Mouse wheel / trackpad | Move the selection |
| `Enter` / click | Apply the selected wallpaper |
| `Ctrl+F` / click the search field | Edit the wallpaper search |
| `Escape` | Close without applying |

While the search field is focused, typing updates the query, `Left` / `Right`
still move the strip, and `Enter` applies the selected wallpaper. Hold `Ctrl`
or `Shift` with the arrows to move the text cursor or select text. `Escape`
clears the query, a second `Escape` leaves the field, and the next one closes
the picker. Search matches file names without their extension,
case-insensitively, and ranks names starting with the query before names that
merely contain it.

`strip.loopMode` selects how the ends behave: `endless` wraps seamlessly,
repeating wallpapers if the folder is smaller than the window; `jump` wraps
instantly between the ends without duplicates; `off` stops at the ends.

The picker closes after a successful apply by default; see `apply.closeOnApply`
in `Config.qml`. If applying fails, it stays open and shows the error. A live
wallpaper keeps playing after the picker closes.

## Configuration

All settings live in [`Config.qml`](Config.qml), and each property is
documented there. The main groups are:

- wallpaper folder and accepted extensions;
- video wallpapers: extensions, poster frame, mpvpaper layer and options, pausing
  when hidden, and the `LIVE` badge;
- live preview clips: enable/disable, length, frame rate, size and quality;
- thumbnail generation, cache and fade-in;
- focused preview crop, size and expansion duration;
- strip height, visible range, pixel spacing, looping, coverflow/focused-tile
  scaling and selection/scroll animation durations;
- overlay layer, background dim and informational messages;
- search mode, field position, margin, opacity and animation duration;
- awww apply transitions, resize, filter and close behaviour.

The cache defaults to `~/.cache/qs-wallpaper-picker` and is safe to delete.

## Notes

- Errors from the scanner, wallpaper queries, `awww img` and `mpvpaper` are
  shown at the bottom of the overlay.
- ImageMagick 7 is required. A missing binary, an unreadable wallpaper folder
  or a file that cannot be converted is reported in the overlay.
- Videos are played with mpvpaper on the `bottom` layer by default, above
  awww's background surface and below normal windows. Change
  `live.layer` if another program also uses that layer.
- Applying a wallpaper replaces any mpvpaper process of the current user.
  Applying an image stops mpvpaper first; applying a video stops it, starts
  the new video and clears awww so no old image or GIF keeps rendering behind
  it. This also stops an mpvpaper started outside the picker.
- Video posters and animated previews are generated during the scan. A folder
  with many videos makes the first scan noticeably longer; the result is
  cached. Set `live.previews.enabled` to `false` to skip clip generation and
  use a static focused crop instead.
- Animated previews are muted 2.5-second WebP clips by default and are
  decoded only while a tile is focused and the strip is not moving. Long or
  high-frame-rate clips use more memory, so keep `live.previews.duration`,
  `fps` and `width` moderate on low-memory machines.
- GIFs are supported, but the first apply and thumbnail generation can be
  slow, and awww's cache may exceed 100 MB per GIF.
- Scanning is non-recursive: only files directly inside the configured folder
  are listed.
- `Config.window.layer` defaults to `overlay`, so the picker covers status
  bars. Set it to `top` to keep bars that also use the overlay layer visible
  above the picker.
- Focused previews are generated and cached during the scan, like thumbnails.
  If a preview is missing or failed, that wallpaper simply does not widen.
- The picker opens on the monitor that has focus at startup and follows focus
  changes while it is open.

## License

MIT
