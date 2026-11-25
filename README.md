<h1 align="center">~ Hyprland wallpaper picker ~</h1>

<p align="center">
  <a href="https://github.com/TheZ3rg/hyprland-wallpaper-picker/commits/main"><img alt="last commit" src="https://img.shields.io/github/last-commit/TheZ3rg/hyprland-wallpaper-picker?style=flat-square&label=last%20commit"></a>
  <a href="https://github.com/TheZ3rg/hyprland-wallpaper-picker/issues"><img alt="open issues" src="https://img.shields.io/github/issues/TheZ3rg/hyprland-wallpaper-picker?style=flat-square&label=issues"></a>
  <a href="https://github.com/TheZ3rg/hyprland-wallpaper-picker/stargazers"><img alt="stars" src="https://img.shields.io/github/stars/TheZ3rg/hyprland-wallpaper-picker?style=flat-square&label=stars&color=67ac09"></a>
  <a href="https://github.com/TheZ3rg/hyprland-wallpaper-picker"><img alt="repo size" src="https://img.shields.io/github/repo-size/TheZ3rg/hyprland-wallpaper-picker?style=flat-square&label=size&color=67ac09"></a>
  <a href="https://github.com/TheZ3rg/hyprland-wallpaper-picker/blob/main/LICENSE"><img alt="license" src="https://img.shields.io/github/license/TheZ3rg/hyprland-wallpaper-picker?style=flat-square&label=license"></a>
  <br>
  <img alt="for Hyprland" src="https://img.shields.io/badge/for-Hyprland-58E1FF?style=flat-square&logo=hyprland&logoColor=00BFFF">
  <img alt="built with Quickshell" src="https://img.shields.io/badge/built%20with-Quickshell-blue?style=flat-square">
</p>

<p align="center"><em>A wallpaper picker for Hyprland with extensive configuration options</em></p>

<p align="center"><img width="1280" height="720" alt="preview" src="https://github.com/user-attachments/assets/a1f18a31-3094-4873-a30e-474863f0cf20"></p>

<p align="center"><strong>A full-screen overlay that allows you to quickly and easily manage your wallpaper collection</strong></p>

<h2 align="center">~ Appearance ~</h2>

<table>
  <tr>
    <td><img src="https://github.com/user-attachments/assets/9ea6a8de-eadc-4d3f-a5f7-595eb9f72e13"/></td>
    <td><img src="https://github.com/user-attachments/assets/77b5a0ff-3771-436b-ac7b-c7961f5024e3"/></td>
  </tr>
  <tr>
    <td><img src="https://github.com/user-attachments/assets/46ba46b7-34da-4ca1-a6df-450f234a22b8"/></td>
    <td><img src="https://github.com/user-attachments/assets/dec96fd7-c6b0-4e62-9e54-1a19eec8d2bd"/></td>
  </tr>
</table>

<h2 align="center">~ Features ~</h2>

- **Easily and extensively customizable appearance.**
- **Supports all major image and video extensions.**
- **Fast startup and responsive interface.**
- **Smooth and customizable animations.**
- **Keyboard, mouse and trackpad navigation.**
- **Fast search by name.**
  
<h2 align="center">~ Dependencies ~</h2>

<h4> Must-have</h4>

- [Hyprland](https://hypr.land) - Wayland compositor.
- [Quickshell](https://quickshell.org) - panel/widget constructor for Wayland.
- [awww](https://codeberg.org/LGFae/awww) - for still wallpapers.
- bash, coreutils, findutils, procps-ng and util-linux - basic linux packets.

<h4> May be useful</h4>

- [mpvpaper](https://github.com/GhostNaN/mpvpaper) - for video wallpapers.
- [ffmpeg](https://ffmpeg.org) - for video posters.
- [ImageMagick 7](https://imagemagick.org) - 

<h2 align="center">~ Setup ~</h2>

1. Install required and additional useful dependencies from the list above.
2. Clone the repository:

   ```sh
   git clone https://github.com/TheZ3rg/hyprland-wallpaper-picker.git
   cd hyprland-wallpaper-picker
   ```

3. Make sure the scripts are executable:

   ```sh
   chmod +x scripts/*.sh
   ```

4. Bind the toggle script in Hyprland. For `hyprland.conf`:

   ```ini
   bind = SUPER, W, exec, /path/to/hyprland-wallpaper-picker/scripts/open-picker.sh
   ```

   For the Lua configuration API:

   ```lua
   hl.bind("SUPER + W", hl.dsp.exec_cmd("/path/to/hyprland-wallpaper-picker/scripts/open-picker.sh"))
   ```

5. Optional: blur the desktop behind the picker:

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
