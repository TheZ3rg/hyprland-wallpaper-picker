# Hyprland wallpaper picker

A coverflow-style wallpaper picker for Hyprland, built with
[Quickshell](https://quickshell.org), [awww](https://codeberg.org/LGFae/awww)
and [mpvpaper](https://github.com/GhostNaN/mpvpaper).

It scans one or more folders, caches thumbnails, and opens as a full-screen
layer-shell overlay on the focused monitor. The desktop behind it is blurred by
Hyprland, not by the picker.

## Features

- Animated coverflow strip with keyboard, mouse and trackpad navigation.
- Scans one or more wallpaper folders (`source.dirs`).
- Optional looping (`strip.loop`): enabled keeps the row continuous and repeats
  wallpapers when needed; disabled stops at the ends.
- Search by wallpaper name: jump to the best match while typing, or hide
  non-matching wallpapers (see `search.mode` in `Config.qml`). Set
  `search.enabled` to `false` to hide the field.
- Only a window of tiles around the selection is instantiated, so large
  folders stay responsive.
- Thumbnail cache keyed by source path and generation options; changing the
  thumbnail size or quality regenerates it automatically.
- The center card shows a wider, higher-resolution crop generated and cached
  during the scan, so it is available as soon as a wallpaper is selected.
- Thumbnails are generated with ImageMagick 7; files that cannot be converted
  are skipped and reported.
- Starts on the wallpaper that is currently displayed.
- GIFs are supported, and animated GIFs are also shown live on the desktop.
- Video wallpapers are played by [mpvpaper](https://github.com/GhostNaN/mpvpaper)
  and appear in the same strip as images.
- Videos and animated GIFs play muted in the center card once the strip
  settles. A cached still preview is shown until the first frame is ready.
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
- ffmpeg, for video posters
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

Set `search.enabled` to `false` to hide the field and disable `Ctrl+F`.

`strip.loop` selects how the ends behave: `true` wraps seamlessly, repeating
wallpapers if the folder is smaller than the window; `false` stops at the ends.

The picker closes after a successful apply by default; see `overlay.closeOnApply`
in `Config.qml`. If applying fails, it stays open and shows the error. A live
wallpaper keeps playing after the picker closes.

## Configuration

All settings live in [`Config.qml`](Config.qml), and each property is
documented there. The main groups are:

- wallpaper folders;
- awww: image/GIF extensions, transitions, resize and filter;
- mpvpaper: video extensions, layer, mpv options and pausing when hidden;
- thumbnail size, quality, cache, fade-in, video poster time and scan workers;
- static preview size and quality, and live playback on/off;
- strip height, spacing ratio, looping, coverflow/center-card scaling, the
  `LIVE` badge and its text size, and move/open animation durations;
- overlay layer, background dim, status text size, informational messages and
  close behaviour;
- search enabled, mode, field size and position, margin ratio, opacity and
  animation duration.

The cache defaults to `~/.cache/qs-wallpaper-picker` and is safe to delete.

## Notes

- Invalid `Config.qml` values raise an error, are listed in the overlay, and
  block applying. Browsing and search still work.
- Errors from the scanner, wallpaper queries, `awww img` and `mpvpaper` are
  shown at the bottom of the overlay.
- ImageMagick 7 is required. A missing binary, an unreadable wallpaper folder
  or a file that cannot be converted is reported in the overlay.
- Videos are played with mpvpaper on the layer selected by `mpvpaper.layer`.
  `background` is the default, but awww also draws there; if the video does
  not appear, use `bottom`, which stays above awww and below normal windows.
- Video audio is controlled by `mpvpaper.options`. Add `no-audio` to mute the
  video, or use `volume=...` to set its volume. Previews are always silent.
- Applying a wallpaper replaces any mpvpaper process of the current user.
  Applying an image stops mpvpaper first; applying a video stops it, starts
  the new video and clears awww so no old image or GIF keeps rendering behind
  it. This also stops an mpvpaper started outside the picker.
- Video posters are generated during the scan, and static previews are cached
  for every wallpaper. Videos and GIFs themselves are not cached: the center
  card decodes them live, starting when the strip settles and stopping as soon
  as the card leaves the center or the row starts moving.
- GIFs are supported, but the first apply and thumbnail generation can be
  slow, and awww's cache may exceed 100 MB per GIF.
- Scanning is non-recursive: only files directly inside the configured folders
  are listed.
- `Config.overlay.layer` defaults to `overlay`, so the picker covers status
  bars. Set it to `top` to keep bars that also use the overlay layer visible
  above the picker.
- Previews are generated and cached during the scan, like thumbnails.
  If a preview is missing or failed, that wallpaper simply does not widen.
- Cache sizes follow the largest connected screen, so moving the picker
  between monitors with different resolutions does not regenerate them.
- The scan processes files in parallel; `thumbnails.workers` sets the number
  of simultaneous conversions (0 picks it from the CPU count).
- The picker opens on the monitor that has focus at startup and follows focus
  changes while it is open.

## License

MIT
