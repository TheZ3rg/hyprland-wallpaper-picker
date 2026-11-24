<h1 align="center">~ Hyprland wallpaper picker ~</h1>

<p align="center"><em>A wallpaper picker for Hyprland with extensive configuration options.</em></p>

<img width="1280" height="720" align="center" alt="preview" src="https://github.com/user-attachments/assets/a1f18a31-3094-4873-a30e-474863f0cf20">

<p align="center"><strong>Fast, beautiful, easily customizable, and built for keyboard/mouse/touchpad control.</strong></p>

<h2 align="center">~ Appearance ~</h2>



<table>
  <tr>
    <td><img src="https://github.com/user-attachments/assets/9ea6a8de-eadc-4d3f-a5f7-595eb9f72e13"/></td>
    <td><img src="https://github.com/user-attachments/assets/77b5a0ff-3771-436b-ac7b-c7961f5024e3"/></td>
  </tr>
  <tr>
    <td><img src="https://github.com/user-attachments/assets/46ba46b7-34da-4ca1-a6df-450f234a22b8"/></td>
    <td><img src="1"/></td>
  </tr>
</table>

<h2 align="center">~ Features ~</h2>

- An animated coverflow strip with keyboard, mouse and trackpad navigation.
- Click a tile or press `Enter` to apply that wallpaper.
- Search by file name as you type; the strip can jump to the best match or
  hide the other wallpapers.
- Images, GIFs and video wallpapers in the same strip, with a `LIVE` badge on
  the ones that move.
- Scans several folders and caches thumbnails, so large collections stay
  responsive.
- Starts on the wallpaper that is currently on your desktop.
- Configurable awww transitions when switching wallpapers.
- Optional seamless looping at the ends of the strip.
- Full-screen overlay; optionally blur the desktop behind it with one
  Hyprland rule.
- One keybind toggles the picker open and closed.
- Errors are shown in the picker instead of failing silently.

<h2 align="center">~ Requirements ~</h2>

- [Hyprland](https://hypr.land) (layer-shell support)
- [Quickshell](https://quickshell.org) (`qs`)
- [awww](https://codeberg.org/LGFae/awww), including `awww-daemon`
- [mpvpaper](https://github.com/GhostNaN/mpvpaper) (with its libmpv
  dependency), for video wallpapers
- [ffmpeg](https://ffmpeg.org), for video posters
- bash, coreutils, findutils, procps-ng and util-linux
- [ImageMagick](https://imagemagick.org) 7 (`magick`)

<h2 align="center">~ Setup ~</h2>

1. Clone the repository:

   ```sh
   git clone https://github.com/TheZ3rg/hyprland-wallpaper-picker.git
   cd hyprland-wallpaper-picker
   ```

2. Make sure the scripts are executable:

   ```sh
   chmod +x scripts/*.sh
   ```

3. Bind the toggle script in Hyprland. For `hyprland.conf`:

   ```ini
   bind = SUPER, W, exec, /path/to/hyprland-wallpaper-picker/scripts/open-picker.sh
   ```

   For the Lua configuration API:

   ```lua
   hl.bind("SUPER + W", hl.dsp.exec_cmd("/path/to/hyprland-wallpaper-picker/scripts/open-picker.sh"))
   ```

4. Optional: blur the desktop behind the picker:

   ```ini
   layerrule = blur, quickshell:wallpaperPicker
   ```

   ```lua
   hl.layer_rule({ match = { namespace = "quickshell:wallpaperPicker" }, blur = true })
   ```

   The namespace is set in `WallpaperPicker.qml`; if you change it, update the
   layer rule to match.

The toggle script starts `awww-daemon` if it is not already running, and
pressing the keybind again closes the picker. Running it directly also works:

```sh
qs -p /path/to/hyprland-wallpaper-picker
```

<h2 align="center">~ Usage ~</h2>

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
clears the query, a second `Escape` leaves the field, and a third closes the
picker. Search matches file names without their extension, case-insensitively,
and ranks names starting with the query before names that merely contain it.

Set `search.enabled` to `false` to hide the field and disable `Ctrl+F`.

`strip.loop` selects how the ends behave: `true` wraps seamlessly, repeating
wallpapers if the folder is smaller than the window; `false` stops at the ends.

The picker closes after a successful apply by default; see
`overlay.closeOnApply` in `Config.qml`. If applying fails, it stays open and
shows the error. A live wallpaper keeps playing after the picker closes.

<h2 align="center">~ Configuration ~</h2>

All settings live in [`Config.qml`](Config.qml), and every property is
documented there. The most common ones are:

| Setting | What it does |
| --- | --- |
| `source.dirs` | Folders scanned for wallpapers; scanning is not recursive. |
| `awww.transition.type` / `duration` | Transition used when applying an image or GIF. |
| `awww.resize` / `filter` | How images fill the screen and how they are scaled. |
| `mpvpaper.enabled` / `options` | Turn video wallpapers on or off and pass extra mpv options, e.g. `no-audio` to mute them. |
| `thumbnails.heightRatio` / `widthRatio` | Tile size in the strip. |
| `strip.loop` | Wrap the strip at the ends. |
| `search.enabled` / `mode` | Show the search field; `scroll` jumps to the best match, `filter` hides non-matching wallpapers. |
| `overlay.closeOnApply` / `backgroundDim` / `layer` | Close after applying, dim the desktop, and choose the layer-shell layer. |

Restart the picker after editing the configuration. The thumbnail cache
defaults to `~/.cache/qs-wallpaper-picker` and is safe to delete.

## License

MIT, see [LICENSE](LICENSE).
