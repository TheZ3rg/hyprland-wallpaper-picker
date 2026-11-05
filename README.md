# Hyprland wallpaper picker

A coverflow-style wallpaper picker for Hyprland, built with
[Quickshell](https://quickshell.org) and [awww](https://codeberg.org/LGFae/awww).

It scans a folder, caches thumbnails, and opens as a full-screen layer-shell
overlay on the focused monitor. The desktop behind it is blurred by Hyprland,
not by the picker.

## Features

- Animated coverflow strip with keyboard, mouse and trackpad navigation.
- Only a window of tiles around the selection is instantiated, so large
  folders stay responsive.
- Thumbnail cache keyed by source path and generation options; changing the
  thumbnail size, mode or corner radius regenerates it automatically.
- Thumbnails are generated with ImageMagick 7; files that cannot be converted
  are skipped and reported.
- Starts on the wallpaper awww is currently displaying.
- Applies wallpapers with configurable awww transitions.
- Shows scan, query and apply errors in the overlay instead of failing silently.
- Single-instance toggle through Quickshell IPC.

## Requirements

- Hyprland (layer-shell support)
- Quickshell (`qs`)
- awww, including `awww-daemon`
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
| `Escape` | Close without applying |

The picker closes after a successful apply by default; see `closeOnApply` in
`Config.qml`. If applying fails, it stays open and shows the error.

## Configuration

All settings live in [`Config.qml`](Config.qml), and each property is
documented there. The main groups are:

- wallpaper folder and accepted extensions;
- thumbnail mode, size, corner radius and cache directory;
- strip height, visible range and coverflow scaling;
- background dim and animation durations;
- awww resize, filter and transition options.

The cache defaults to `~/.cache/qs-wallpaper-picker` and is safe to delete.

## Notes

- Errors from the scanner, `awww query` and `awww img` are shown at the bottom
  of the overlay.
- ImageMagick 7 is required. A missing binary, an unreadable wallpaper folder
  or a file that cannot be converted is reported in the overlay.
- GIFs are supported, but the first apply and thumbnail generation can be
  slow, and awww's cache may exceed 100 MB per GIF.
- Scanning is non-recursive: only files directly inside the configured folder
  are listed.
- The picker opens on the monitor that has focus at startup and follows focus
  changes while it is open.

## License

MIT
