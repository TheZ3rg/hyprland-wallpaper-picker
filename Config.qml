pragma Singleton

import QtQuick
import Quickshell

/// User-facing settings. Every tunable of the picker lives here.
///
/// Restart the picker after editing.
///
/// Groups:
///   Source            directories scanned for wallpapers
///   awww              images and GIFs
///   mpvpaper          video wallpapers
///   Thumbnails        small tiles in the strip
///   Previews          enlarged image or clip of the selected wallpaper
///   Strip             coverflow layout and animations
///   Overlay           the full-screen picker itself
///   Search            search field and matching
///
/// Terms:
///   awww         displays images and GIFs
///   mpvpaper     plays video wallpapers
///   thumbnail    small image in the strip
///   preview      enlarged image or clip of the selected wallpaper
Singleton {
    id: root

    // ── SOURCE ────────────────────────────────────────────────

    /// The wallpaper source.
    property QtObject source: QtObject {
        /// Folder scanned for wallpapers.
        ///
        /// Scanning is not recursive.
        /// Use an absolute path; "~" is not expanded.
        ///
        /// Example: "/home/user/Pictures/Wallpapers"
        property string dir: Quickshell.env("HOME") + "/Pictures/Wallpapers"
    }

    // ── AWWW ──────────────────────────────────────────────────

    /// How awww displays images and GIFs.
    ///
    /// Transitions, resize and filter apply to awww (images and GIFs).
    /// Videos are played by mpvpaper and ignore these; use mpvpaper.options
    /// for video playback settings.
    property QtObject awww: QtObject {
        /// Image file extensions, without the dot.
        ///
        /// Handled by awww, GIFs belong here for this reason.
        /// Lower-case is recommended.
        ///
        /// Example: ["jpg", "jpeg", "png", "webp", "gif"]
        property var extensions: ["jpg", "jpeg", "png", "webp", "gif"]

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
            /// Invalid values raise an error and block applying.
            property string type: "grow"

            /// Transition duration in milliseconds.
            ///
            /// Has no effect when type is "none".
            ///
            /// Example: 800 = 800 milliseconds, 0 = instant.
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
        /// Invalid values raise an error and block applying.
        property string resize: "cover"

        /// Scaling filter for awww.
        ///
        /// Possible values:
        ///   "Nearest"     fastest; best for pixel art
        ///   "Bilinear"    fast and soft
        ///   "CatmullRom"  good quality/speed balance
        ///   "Mitchell"    softer
        ///   "Lanczos3"    sharpest, slowest
        ///
        /// Use the exact spelling. Invalid names raise an error and block applying.
        property string filter: "Lanczos3"
    }

    // ── MPVPAPER ──────────────────────────────────────────────

    /// Video wallpapers are played by mpvpaper.
    property QtObject mpvpaper: QtObject {
        /// Enable video wallpapers.
        ///
        /// Set to false to ignore video files and use only images/GIFs.
        property bool enabled: true

        /// Video file extensions, without the dot.
        ///
        /// This is only a filename filter: mpvpaper can play any format mpv
        /// can decode. Thumbnails and previews also need ffmpeg support.
        /// Lower-case is recommended.
        ///
        /// Example: ["mp4", "webm", "mkv", "mov", "m4v"]
        property var extensions: ["mp4", "webm", "mkv", "mov", "m4v"]

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
        /// Invalid values raise an error and block applying.
        property string layer: "background"

        /// Extra mpv options for the desktop video.
        ///
        /// Appended after "loop". Use mpv config syntax, separated by spaces.
        /// Invalid options can prevent mpvpaper from starting.
        /// Recommended to change one option at a time.
        ///
        /// Possible options:
        ///    Audio:
        ///      "no-audio"                      mute the video
        ///      "volume=40"                     volume, 0..100
        ///      "audio-device=..."              choose the output device
        ///
        ///    Performance:
        ///      "hwdec=auto-safe"               hardware decoding when possible
        ///      "profile=fast"                  lower quality, less CPU/GPU work
        ///      "profile=high-quality"          better scaling, more GPU work
        ///
        ///    Motion and timing:
        ///      "vf=fps=30"                     drop/duplicate frames to 30 fps
        ///      "speed=1.3"                     play faster
        ///      "interpolation=yes"             smoother motion, more GPU work
        ///      "video-sync=display-resample"   sync playback to the display
        ///
        ///    Fit and crop:
        ///      "panscan=1.0"                   crop letterbox/pillarbox bars
        ///      "video-rotate=90"               rotate portrait videos
        ///
        ///    Picture:
        ///      "brightness=-10"                darken (-100..100)
        ///      "contrast=10"                   increase contrast (-100..100)
        ///      "saturation=-20"                desaturate (-100..100)
        ///      "deband=yes"                    reduce banding, more GPU work
        ///      "glsl-shaders=/path/file.glsl"  use a shader, GPU-heavy
        ///
        ///    Clean output:
        ///      "sub-auto=no"                   do not auto-load subtitles
        ///      "sid=no"                        disable embedded subtitles
        ///      "osd-level=0"                   no on-screen messages
        property string options: "speed=1.3 vf=fps=60 brightness=-10"

        /// Pause the video when its wallpaper surface is hidden, and resume
        /// when it is visible again .
        ///
        /// Uses mpvpaper --auto-pause.
        /// See autoPauseMode property for more advanced configuration.
        property bool pauseWhenHidden: true

        /// Extend pauseWhenHidden, configure when pause occurs.
        ///
        /// Ignored when pauseWhenHidden is false. Invalid values still raise an error.
        ///
        /// Possible values:
        ///   ""      only the compositor's hidden detection
        ///   "full"  also pause when any fullscreen window is open
        ///   "max"   also pause when a fullscreen or maximized window is open
        property string autoPauseMode: "max"
    }

    // ── THUMBNAILS AND PREVIEWS ───────────────────────────────

    /// Small images shown in the strip.
    ///
    /// They are generated during the scan and cached. Changing the size or
    /// corner radius regenerates them.
    property QtObject thumbnails: QtObject {
        /// Base tile size as fractions of the monitor height.
        ///
        /// Both values use screen height, so the tile aspect stays the same on
        /// monitors with different aspect ratios. They also set the size of the
        /// cached thumbnails.
        ///
        /// Example: heightRatio 0.35 and widthRatio 0.28.
        property real heightRatio: 0.35
        property real widthRatio: 0.28

        /// Rounded corner radius in pixels.
        ///
        /// Baked into the cached thumbnail; changing it regenerates the cache.
        /// 0 keeps rectangular corners. The radius does not scale with the
        /// screen.
        /// TODO: experimental function, needs testing and fixing.
        property int cornerRadius: 0

        /// Where thumbnails and previews are cached.
        ///
        /// Safe to delete; the next scan rebuilds it.
        ///
        /// Example: "/home/user/.cache/qs-wallpaper-picker"
        property string cacheDir: Quickshell.env("HOME") + "/.cache/qs-wallpaper-picker"

        /// Fade-in time for each thumbnail after it loads, in milliseconds.
        ///
        /// Example: 800 = 800 milliseconds, 0 = no fade.
        property int fadeInDuration: 800

        /// Time into the video used for its still thumbnail and as the start
        /// of its animated preview, in seconds.
        ///
        /// Falls back to the first frame when the video is shorter.
        ///
        /// Example: 1.0 = 1 second into the video.
        property real videoPosterSeek: 1.0
    }

    /// The larger image shown in the center card.
    ///
    /// It is generated during the scan and cached. Changing its size or aspect
    /// regenerates it. This is independent of the animated clips in
    /// previews.animated.
    property QtObject previews: QtObject {
        /// Enable the enlarged image.
        property bool enabled: true

        /// Preview size as multiples of the thumbnail size.
        ///
        /// widthScale and heightScale multiply the thumbnail width and height
        /// for both the center card and its cached preview. They are display
        /// multipliers, not just resolution.
        ///
        /// Higher values increase card size, scan time, cache size and memory.
        ///
        /// Example: 1.2 and 1.2 make the center card 1.2x the thumbnail size.
        property real heightScale: 1.2
        property real widthScale: 1.2

        /// Cache directory for previews.
        ///
        /// Kept separate from thumbnails so the scan's cache cleanup does not
        /// delete previews. You normally do not need to change it.
        ///
        /// Example: "/home/user/.cache/qs-wallpaper-picker/previews"
        property string cacheDir: root.thumbnails.cacheDir + "/previews"

        /// Short muted clips shown in the center card.
        ///
        /// They are generated during the scan and cached. Changing the clip
        /// settings regenerates them. When disabled, videos and GIFs still get
        /// a static enlarged image in the center card.
        property QtObject animated: QtObject {
            /// Enable animated previews.
            property bool enabled: false

            /// Preview clip length in milliseconds.
            ///
            /// Example: 2500 = 2.5 seconds.
            property int duration: 3000

            /// Clip frame rate.
            ///
            /// Higher is smoother but uses more memory and scan time.
            ///
            /// Example: 24 = 24 frames per second.
            property int fps: 24

            /// Clip width in pixels.
            ///
            /// The height follows the center card aspect. This is intentionally
            /// smaller than the static preview because an animated clip
            /// decodes many frames; a few hundred pixels is usually enough.
            ///
            /// Example: 600 = 600 pixels wide.
            /// TODO: make this a fraction of the screen width and fix the docs.
            property int width: 600

            /// WebP encoder quality, 1..100.
            ///
            /// Higher is bigger and sharper.
            property int quality: 60
        }
    }

    // ── STRIP AND COVERFLOW ───────────────────────────────────

    /// Layout and animation of the horizontal coverflow row.
    property QtObject strip: QtObject {
        /// What happens at the ends of the list.
        ///
        /// Possible values:
        ///   "endless"  wrap forever, repeating wallpapers if needed
        ///   "off"      stop at the ends
        ///
        /// Invalid values raise an error and block applying.
        property string loopMode: "endless"

        /// Gap between tiles in pixels.
        ///
        /// Unlike tile sizes, it does not scale with the screen.
        /// TODO: make this a fraction of the screen size and fix the docs.
        property int spacing: 8

        /// Time for an input-driven move, in milliseconds.
        ///
        /// One arrow step, wheel/trackpad input, and catching up after holding
        /// a key.
        ///
        /// Example: 500 = 0.5 seconds; 0 makes these moves instant.
        property int selectionDuration: 600

        /// Duration of the opening scroll when the picker starts, in
        /// milliseconds.
        ///
        /// Example: 600 = 0.6 seconds; 0 makes the opening scroll instant.
        property int scrollDuration: 600

        /// Scale tiles down toward the strip edges (the coverflow effect).
        ///
        /// Disable to keep every tile at the same scale
        /// TODO: make coverflow an QtObject with related properties.
        property bool coverflowEnabled: false

        /// Scale of the center tile and of tiles falloffRange slots away.
        ///
        /// 1.35 = 35% larger than the base tile; 0.6 = 60%.
        property real centerScale: 1.35
        property real edgeScale: 0.6

        /// Number of tiles over which the scale falls from centerScale to
        /// edgeScale.
        ///
        /// Example: 9 = the 9th tile away from the centre is at edgeScale.
        property real falloffRange: 9.0

        /// Extra size multipliers for the center card.
        ///
        /// centerWidthScale widens the card and centerHeightScale lengthens it.
        /// They are ignored unless coverflowEnabled is true.
        ///
        /// Example: 1.35 = 35% wider/higher than the base tile; 1.0 = same width/height.
        property real centerWidthScale: 1.0
        property real centerHeightScale: 1.0

        /// Show the "LIVE" badge on video and GIF tiles.
        property bool showLiveBadge: true
    }

    // ── OVERLAY WINDOW ────────────────────────────────────────

    /// The full-screen picker overlay.
    property QtObject overlay: QtObject {
        /// Layer-shell layer of the picker itself.
        ///
        /// Possible values:
        ///   "overlay"     covers panels and bars (default)
        ///   "top"         keeps overlay-layer bars above the picker
        ///   "bottom"      under normal windows; rarely useful
        ///   "background"  under everything; rarely useful
        ///
        /// Invalid values raise an error and block applying.
        property string layer: "overlay"

        /// Darkness of the overlay over the desktop, 0..1.
        ///
        /// Example: 0.2 = 20% opaque black, 0 = no dimming, 1 = fully black.
        property real backgroundDim: 0.2

        /// Show informational messages at the bottom.
        ///
        /// Covers scan/apply progress, search counts and the empty-folder
        /// hint. Errors are always shown.
        property bool showInfoNotifications: true

        /// Close the picker after a wallpaper has been applied successfully.
        property bool closeOnApply: true
    }

    // ── SEARCH ────────────────────────────────────────────────

    /// Search field and how the query affects the strip.
    property QtObject search: QtObject {
        /// How the strip responds to a query.
        ///
        /// Possible values:
        ///   "scroll"  jump to the best match as you type
        ///   "filter"  hide wallpapers that do not match
        ///
        /// Invalid values raise an error and block applying.
        property string mode: "scroll"

        /// Horizontal position of the search field.
        ///
        /// Possible values: "left", "center", "right".
        ///
        /// Invalid values raise an error and block applying.
        property string horizontalAlignment: "center"

        /// Vertical position of the search field.
        ///
        /// Possible values: "top", "center", "bottom".
        ///
        /// Invalid values raise an error and block applying.
        property string verticalAlignment: "bottom"

        /// Distance from the chosen screen edges, in pixels.
        ///
        /// Example: 15 = 15 pixels from the edge.
        /// TODO: make this a fraction of the screen size and fix the docs.
        property int margin: 15

        /// Opacity of the search field when it is not being edited.
        ///
        /// Example: 0 - fully transparent 1 - fully opaque.
        property real unfocusedOpacity: 1

        /// Animation time for search jumps, in milliseconds.
        ///
        /// 0 is instant. Short jumps still use strip.selectionDuration.
        /// TODO: strange use of strip.selectionDuration for short jumps; needs fixing.
        property int animationDuration: 800
    }
}
