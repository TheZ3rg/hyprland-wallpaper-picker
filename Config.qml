pragma Singleton

import QtQuick
import Quickshell

/// User-facing settings. Every tunable of the picker lives here.
///
/// This file is QML. Strings use double quotes "...", lists use [ ... ],
/// booleans are true/false, and decimals use a dot (1.0). Comments start with
/// // and are ignored. Restart the picker after editing.
///
/// Groups:
///   Source            files scanned for wallpapers
///   Live wallpapers   videos played by mpvpaper
///   Thumbnails        small tiles in the strip
///   Previews          enlarged image of the selected tile
///   Strip             coverflow layout and animations
///   Overlay window    the full-screen picker itself
///   Search            search field and matching
///   Apply             awww transitions and closing behaviour
///
/// Terms:
///   awww       displays images and GIFs
///   mpvpaper   plays video wallpapers
///   thumbnail  small image in the strip
///   preview    enlarged image or clip of the selected wallpaper
Singleton {
    id: root

    // ── Source ────────────────────────────────────────────────

    /// Folder scanned for wallpapers. Scanning is not recursive.
    ///
    /// Use an absolute path; "~" is not expanded.
    ///
    /// Example: "/home/user/Pictures/Wallpapers"
    property string wallpaperDir: Quickshell.env("HOME") + "/Pictures/Wallpapers"

    /// Image file extensions, without the dot.
    ///
    /// Handled by awww, GIFs belong here for this reason.
    /// Lower-case is recommended.
    property var extensions: ["jpg", "jpeg", "png", "webp", "gif"]

    // ── Live wallpapers ───────────────────────────────────────

    /// Video wallpapers are played by mpvpaper.
    property QtObject live: QtObject {
        /// Enable video wallpapers.
        ///
        /// Set to false to ignore video files and use only images/GIFs.
        property bool enabled: true

        /// Video file extensions, without the dot.
        ///
        /// This is only a filename filter: mpvpaper can play any format mpv
        /// can decode. Thumbnails and previews also need ffmpeg support.
        /// Lower-case is recommended.
        property var extensions: ["mp4", "webm", "mkv", "mov", "m4v"]

        /// Time into the video used for its still thumbnail and as the start
        /// of its animated preview, in seconds.
        ///
        /// Falls back to the first frame when the video is shorter.
        ///
        /// Example: 1.0 = 1 second into the video.
        property real posterSeek: 1.0

        /// Show the "LIVE" badge on video and GIF tiles.
        property bool showBadge: true

        /// Wayland layer used by mpvpaper for the video.
        ///
        /// Possible values:
        ///   "background"   mpvpaper's own default, but awww also draws there;
        ///                  if the video does not appear, change this to
        ///                  "bottom".
        ///   "bottom"       keeps the video above awww and below normal
        ///                  windows.
        ///   "top"          draw over normal windows and so are not useful
        ///                  for a wallpaper.
        ///   "overlay"      draw over everything and so are not useful for a
        ///                  wallpaper.
        ///
        /// Unknown values fall back to "background".
        property string layer: "background"

        /// Extra mpv options for the desktop video.
        ///
        /// Appended after "loop". Use mpv config syntax, separated by spaces.
        /// Quote values that contain spaces. Add "no-audio" to mute the video;
        /// remove it to let the video play sound.
        ///
        /// Audio:
        ///   "no-audio"                      mute the video
        ///   "volume=40"                     volume, 0..100
        ///   "audio-device=..."              choose the output device
        ///
        /// Performance:
        ///   "hwdec=auto-safe"               hardware decoding when possible
        ///   "profile=fast"                  lower quality, less CPU/GPU work
        ///   "profile=high-quality"          better scaling, more GPU work
        ///
        /// Motion and timing:
        ///   "vf=fps=30"                     drop/duplicate frames to 30 fps
        ///   "speed=1.3"                     play faster
        ///   "interpolation=yes"             smoother motion, more GPU work
        ///   "video-sync=display-resample"   sync playback to the display
        ///
        /// Fit and crop:
        ///   "panscan=1.0"                   crop letterbox/pillarbox bars
        ///   "video-rotate=90"               rotate portrait videos
        ///
        /// Picture:
        ///   "brightness=-10"                darken (-100..100)
        ///   "contrast=10"                   increase contrast (-100..100)
        ///   "saturation=-20"                desaturate (-100..100)
        ///   "deband=yes"                    reduce banding, more GPU work
        ///   "glsl-shaders=/path/file.glsl"  use a shader, GPU-heavy
        ///
        /// Clean output:
        ///   "sub-auto=no"                   do not auto-load subtitles
        ///   "sid=no"                        disable embedded subtitles
        ///   "osd-level=0"                   no on-screen messages
        ///
        /// Invalid options can prevent mpvpaper from starting. Change one
        /// option at a time.
        property string mpvOptions: "speed=1.3"

        /// Pause the video when its wallpaper surface is hidden, and resume
        /// when it is visible again (mpvpaper --auto-pause).
        ///
        /// See autoPauseMode property for more information.
        property bool pauseWhenHidden: true

        /// Extend pauseWhenHidden, configure when pause occurs.
        ///
        /// Possible values:
        ///   ""      only the compositor's hidden detection
        ///   "full"  also pause when any fullscreen window is open
        ///   "max"   also pause when a fullscreen or maximized window is open
        ///
        /// Ignored when pauseWhenHidden is false. Unknown values are ignored.
        property string autoPauseMode: "max"

        /// Short muted clips shown in the focused tile.
        ///
        /// They are generated during the scan and cached. Changing the clip
        /// settings regenerates them. When disabled, videos and GIFs still get
        /// a static enlarged image, so they can still be focused.
        property QtObject previews: QtObject {
            /// Enable animated previews.
            property bool enabled: true

            /// Preview clip length in milliseconds.
            ///
            /// Example: 2500 = 2.5 seconds.
            property int duration: 2500

            /// Clip frame rate.
            ///
            /// Higher is smoother but uses more memory and scan time.
            ///
            /// Example: 12 = 12 frames per second.
            property int fps: 12

            /// Clip width in pixels.
            ///
            /// The height follows the focused tile aspect:
            /// previews.aspectRatio * strip.focusWidthScale.
            /// This is intentionally smaller than previews.height because an
            /// animated clip decodes many frames; a few hundred pixels is
            /// usually enough.
            property int width: 400

            /// WebP encoder quality, 1..100.
            ///
            /// Higher is bigger and sharper.
            property int quality: 60
        }
    }

    // ── Thumbnails and focused previews ───────────────────────

    /// Small images shown in the strip.
    ///
    /// They are generated during the scan and cached. Changing the size, mode
    /// or corner radius regenerates them.
    property QtObject thumbnails: QtObject {
        /// Thumbnail shape.
        ///
        /// Possible values:
        ///   "cover"     crop every image to width x height; all tiles have the
        ///               same shape
        ///   "preserve"  keep each image's own aspect ratio and fit it inside
        ///               the box
        ///
        /// Other values cause the scan to fail.
        property string mode: "cover"

        /// Thumbnail box size in pixels.
        ///
        /// In "cover" mode every thumbnail is exactly width x height. In
        /// "preserve" mode the real size is often smaller and is read back
        /// from the generated file.
        property int width: 340
        property int height: 800

        /// Rounded corner radius in pixels.
        ///
        /// Baked into the cached thumbnail; changing it regenerates the cache.
        /// 0 keeps rectangular corners. The radius does not scale with the
        /// screen.
        property int cornerRadius: 0

        /// Where thumbnails and previews are cached.
        ///
        /// Safe to delete; the next scan rebuilds it.
        property string cacheDir: Quickshell.env("HOME") + "/.cache/qs-wallpaper-picker"

        /// Fade-in time for each thumbnail after it loads, in milliseconds.
        ///
        /// 0 disables the fade.
        property int fadeInDuration: 800
    }

    /// The larger image shown for the selected (focused) tile.
    ///
    /// It is generated during the scan and cached. Changing its size or aspect
    /// regenerates it. This is independent of the animated clips in
    /// live.previews.
    property QtObject previews: QtObject {
        /// Enable the enlarged image.
        property bool enabled: true

        /// Shape of the focused image, as width / height.
        ///
        /// 0.8 = 4:5 portrait, 0.75 = 3:4, 1.0 = square, 1.33 = 4:3.
        /// strip.focusWidthScale multiplies this.
        property real aspectRatio: 0.8

        /// Height of the focused preview in pixels.
        ///
        /// The width follows aspectRatio. Higher values are sharper but
        /// increase scan time, cache size and memory. Keep it at least as tall
        /// as the displayed card to avoid upscaling.
        property int height: 1000

        /// How long the selected card takes to widen, in milliseconds.
        ///
        /// 0 makes it instant.
        property int expandDuration: 240

        /// Start widening this many milliseconds before a long scroll ends.
        ///
        /// This overlaps the two animations. The lead never exceeds
        /// expandDuration. 0 waits for the scroll to finish.
        property int expandOverlap: 250

        /// Cache directory for focused previews.
        ///
        /// Kept separate from thumbnails so the scan's cache cleanup does not
        /// delete previews. You normally do not need to change it.
        property string cacheDir: root.thumbnails.cacheDir + "/previews"
    }

    // ── Strip and coverflow ───────────────────────────────────

    /// Layout and animation of the horizontal coverflow row.
    property QtObject strip: QtObject {
        /// Height of the centred tile as a fraction of the screen height.
        ///
        /// 0.28 = 28% of the screen height. Other tile sizes derive from it.
        property real itemHeightRatio: 0.28

        /// Number of tiles around the selection that stay loaded.
        ///
        /// Larger values make distant scrolling smoother but use more memory.
        property int visibleRange: 30

        /// What happens at the ends of the list.
        ///
        /// Possible values:
        ///   "endless"  wrap forever, repeating wallpapers if needed
        ///   "jump"     jump instantly from one end to the other (experimental)
        ///   "off"      stop at the ends
        ///
        /// Unknown values fall back to "off".
        // TODO: fix the "jump" mode
        property string loopMode: "endless"

        /// Gap between tiles in pixels.
        ///
        /// Unlike tile sizes, it does not scale with the screen.
        property int spacing: 8

        /// Time for a one-step move (arrow, wheel, trackpad), in milliseconds.
        ///
        /// 0 makes it instant.
        property int selectionDuration: 500

        /// Time for a long scroll to a distant wallpaper when the picker opens,
        /// in milliseconds.
        ///
        /// 0 makes it instant.
        property int scrollDuration: 800

        /// Scale tiles down toward the strip edges (the coverflow effect).
        ///
        /// Disable to keep every tile at the same scale.
        property bool coverflowEnabled: true

        /// Scale of the centred tile and of tiles falloffRange slots away.
        ///
        /// 1.4 = 40% larger than the base tile; 0.6 = 60%.
        property real centerScale: 1.4
        property real edgeScale: 0.6

        /// Number of tiles over which the scale falls from centerScale to
        /// edgeScale.
        property real falloffRange: 9.0

        /// Extra size multipliers for the focused tile.
        ///
        /// 1 = unchanged. focusWidthScale widens the card (it multiplies
        /// previews.aspectRatio); focusHeightScale makes it taller. The wider
        /// card appears once the preview is ready.
        property real focusWidthScale: 1.35
        property real focusHeightScale: 1.0
    }

    // ── Overlay window ────────────────────────────────────────

    /// The full-screen picker overlay.
    property QtObject window: QtObject {
        /// Layer-shell layer of the picker itself.
        ///
        /// Possible values:
        ///   "overlay"     covers panels and bars (default)
        ///   "top"         keeps overlay-layer bars above the picker
        ///   "bottom"      under normal windows; rarely useful
        ///   "background"  under everything; rarely useful
        ///
        /// Unknown values fall back to "overlay".
        property string layer: "overlay"

        /// Darkness of the overlay over the desktop, 0..1.
        ///
        /// 0 = transparent, 1 = black. The desktop is blurred by a Hyprland
        /// layer rule; blur strength is a compositor setting.
        property real backgroundDim: 0.2

        /// Show informational messages at the bottom.
        ///
        /// Covers scan/apply progress, search counts and the empty-folder
        /// hint. Errors are always shown.
        property bool showInfoNotifications: true
    }

    // ── Search ────────────────────────────────────────────────

    /// Search field and how the query affects the strip.
    property QtObject search: QtObject {
        /// How the strip responds to a query.
        ///
        /// Possible values:
        ///   "scroll"  jump to the best match as you type
        ///   "filter"  hide wallpapers that do not match
        ///
        /// Unknown values fall back to "scroll".
        property string mode: "scroll"

        /// Horizontal position.
        ///
        /// Possible values: "left", "center", "right".
        ///
        /// Unknown values fall back to "center".
        property string horizontalAlignment: "center"

        /// Vertical position.
        ///
        /// Possible values: "top", "center", "bottom".
        ///
        /// Unknown values fall back to "top".
        property string verticalAlignment: "bottom"

        /// Distance from the chosen screen edges, in pixels.
        property int margin: 15

        /// Opacity of the search field when it is not being edited.
        ///
        /// Example: 0 - fully transparent 1 - fully opaque.
        property real unfocusedOpacity: 0

        /// Animation time for search jumps, in milliseconds.
        ///
        /// 0 is instant. Short jumps still use strip.selectionDuration.
        property int animationDuration: 800
    }

    // ── Apply and quit ────────────────────────────────────────

    /// What happens after choosing a wallpaper.
    ///
    /// Transitions, resize and filter apply to awww (images and GIFs).
    /// Videos are played by mpvpaper and ignore these; use live.mpvOptions
    /// for video playback settings.
    property QtObject apply: QtObject {
        /// Close the picker after a wallpaper has been applied successfully.
        property bool closeOnApply: true

        /// Transition settings for awww (images and GIFs).
        property QtObject transition: QtObject {
            /// Transition type when the wallpaper changes.
            ///
            /// Possible values:
            ///   "none"  instant
            ///   "grow"  expands from the centre
            ///   "wipe"  sweeps across (see angle)
            ///   "fade"  cross-fades
            ///   "wave"  wavy wipe
            ///
            /// Unknown values fall back to "grow".
            property string type: "grow"

            /// Transition duration in milliseconds.
            ///
            /// Has no effect when type is "none".
            property int duration: 800

            /// Transition frame rate.
            ///
            /// Higher is smoother but uses more CPU.
            ///
            /// Example: 120 = 120 frames per second.
            property int fps: 120

            /// Wipe angle in degrees.
            ///
            /// Example: 0 sweeps right-to-left, 90 top-to-bottom.
            property int angle: 30
        }

        /// How awww fits images and GIFs on the screen.
        ///
        /// Possible values:
        ///   "cover"    fills the screen and crops the overflow
        ///   "contain"  fits the whole image inside it
        ///   "fill"     stretches it
        ///
        /// Unknown values fall back to "cover".
        property string resize: "contain"

        /// Scaling filter for awww.
        ///
        /// Possible values:
        ///   "Nearest"     fastest; best for pixel art
        ///   "Bilinear"    fast and soft
        ///   "CatmullRom"  good quality/speed balance
        ///   "Mitchell"    softer
        ///   "Lanczos3"    sharpest, slowest
        ///
        /// Use the exact spelling. Invalid names can fail the apply.
        property string filter: "Lanczos3"
    }
}
