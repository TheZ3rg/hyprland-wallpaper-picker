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
///   Previews          enlarged image of the selected wallpaper
///   Strip             coverflow layout and animations
///   Overlay           the full-screen picker itself
///   Search            search field and matching
///
/// Terms:
///   awww         displays images and GIFs
///   mpvpaper     plays video wallpapers
///   thumbnail    small image in the strip
///   preview      enlarged image of the selected wallpaper
Singleton {
    id: root

    // ── SOURCE ────────────────────────────────────────────────

    /// The wallpaper sources.
    property QtObject source: QtObject {
        /// Folders scanned for wallpapers.
        ///
        /// Scanning is not recursive. Use absolute paths; "~" is not expanded.
        /// Duplicate entries are ignored.
        ///
        /// Example:
        /// [
        ///     "/home/user/Pictures/Wallpapers",
        ///     "/mnt/media/Wallpapers"
        /// ]
        property var dirs: [
            Quickshell.env("HOME") + "/Pictures/Wallpapers",
            Quickshell.env("HOME") + "/Pictures/Wallpapers-live"
        ]
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
            property string type: "wipe"

            /// Transition duration in milliseconds.
            ///
            /// Has no effect when type is "none".
            ///
            /// Example: 800 = 0.8 seconds, 0 = instant.
            property int duration: 1200

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
        /// Ignored when pauseWhenHidden is false.
        ///
        /// Possible values:
        ///   ""      only the compositor's hidden detection
        ///   "full"  also pause when any fullscreen window is open
        ///   "max"   also pause when a fullscreen or maximized window is open
        ///
        /// Invalid values raise an error and block applying.
        property string autoPauseMode: "max"
    }

    // ── THUMBNAILS AND PREVIEWS ───────────────────────────────

    /// Small images shown in the strip.
    ///
    /// They are generated during the scan and cached. Changing the size or
    /// quality regenerates them.
    property QtObject thumbnails: QtObject {
        /// Base tile size as fractions of the monitor height.
        ///
        /// Both values use screen height, so the tile aspect stays the same on
        /// monitors with different aspect ratios. They also set the size of the
        /// cached thumbnails, which follow the largest connected screen.
        ///
        /// Example: heightRatio 0.35 and widthRatio 0.28.
        property real heightRatio: 0.32
        property real widthRatio: 0.18

        /// Quality of the cached thumbnails, 1..100.
        ///
        /// Higher values are sharper but increase cache size and scan time.
        /// This does not affect the wallpaper displayed on the desktop.
        property int quality: 85

        /// Where thumbnails and previews are cached.
        ///
        /// Safe to delete; the next scan rebuilds it.
        ///
        /// Example: "/home/user/.cache/qs-wallpaper-picker"
        property string cacheDir: Quickshell.env("HOME") + "/.cache/qs-wallpaper-picker"

        /// Fade-in time for each thumbnail after it loads, in milliseconds.
        ///
        /// Example: 800 = 800 milliseconds, 0 = no fade.
        property int fadeInDuration: 600

        /// Number of files processed at the same time during the scan.
        ///
        /// 0 picks a value from the CPU count. Higher values make the first
        /// scan faster but use more CPU and memory.
        property int workers: 0

        /// Time into the video used for its still thumbnail, static preview
        /// and the start of its live preview, in seconds.
        ///
        /// Falls back to the first frame when the video is shorter.
        ///
        /// Example: 1.0 = 1 second into the video.
        property real videoPosterSeek: 1.0
    }

    /// The larger image shown in the center card.
    ///
    /// It is generated during the scan and cached. Changing its size, aspect or
    /// quality regenerates it. Videos and GIFs play live in the card; this
    /// image is shown until their first frame is ready.
    property QtObject previews: QtObject {
        /// Enable the enlarged image.
        property bool enabled: true

        /// Preview size as multiples of the thumbnail size.
        ///
        /// widthScale and heightScale multiply the thumbnail width and height
        /// for both the center card and its cached preview.
        ///
        /// Example: 1.2 and 1.2 make the center card 1.2x the thumbnail size.
        property real heightScale: 1.15
        property real widthScale: 2.4

        /// Quality of the cached static preview image, 1..100.
        ///
        /// Higher values are sharper but increase cache size and scan time.
        /// This does not affect the wallpaper displayed on the desktop.
        property int quality: 85

        /// Cache directory for previews.
        ///
        /// Kept separate from thumbnails so the scan's cache cleanup does not
        /// delete previews. You normally do not need to change it.
        ///
        /// Example: "/home/user/.cache/qs-wallpaper-picker/previews"
        property string cacheDir: root.thumbnails.cacheDir + "/previews"

        /// Play videos and GIFs in the center card.
        property QtObject live: QtObject {
            /// Enable live playback.
            ///
            /// When false, videos and GIFs show only their static preview and
            /// the multimedia backend is never loaded.
            property bool enabled: true
        }
    }

    // ── STRIP AND COVERFLOW ───────────────────────────────────

    /// Layout and animation of the horizontal wallpaper row.
    property QtObject strip: QtObject {
        /// Wrap the row forever, repeating wallpapers if needed.
        ///
        /// When false, the strip stops at the ends.
        property bool loop: true

        /// Gap between tiles as a fraction of the monitor height.
        ///
        /// Example: 0.006 = 0.6% of the monitor height.
        property real spacingRatio: 0.006

        /// Time for an input-driven move, in milliseconds.
        ///
        /// One arrow step, wheel/trackpad input, and catching up after holding
        /// a key.
        ///
        /// Example: 500 = 0.5 seconds; 0 makes these moves instant.
        property int moveAnimationDuration: 600

        /// Duration of the opening scroll when the picker starts, in
        /// milliseconds.
        ///
        /// Example: 600 = 0.6 seconds; 0 makes the opening scroll instant.
        property int openAnimationDuration: 0

        /// Scale tiles down toward the strip edges (coverflow).
        ///
        /// Disable to keep every tile at the same scale.
        property QtObject coverflow: QtObject {
            /// The other coverflow settings are ignored when disabled.
            property bool enabled: true

            /// Scale of the center tile and of tiles falloffRange slots away.
            ///
            /// Example: 1.35 = 135% of the base size;
            ///          0.6 = 60% of the base size.
            property real centerScale: 1.0
            property real edgeScale: 0.6

            /// Number of tiles over which the scale falls from centerScale to
            /// edgeScale.
            ///
            /// Example: 9 = the 9th tile away from the centre is at edgeScale.
            property real falloffRange: 9.0
        }

        /// Show the "LIVE" badge on video and GIF tiles.
        property bool showLiveBadge: true

        /// Text size of the "LIVE" badge, in logical pixels.
        ///
        /// The badge's padding, corner radius and the tile width at which it
        /// is hidden follow this size.
        property int liveBadgeFontSize: 10
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

        /// Text size of the status message at the bottom, in logical pixels.
        ///
        /// The box's padding and corner radius follow this size. Errors are
        /// shown at this size too.
        property int statusFontSize: 14

        /// Close the picker after a wallpaper has been applied successfully.
        property bool closeOnApply: true
    }

    // ── SEARCH ────────────────────────────────────────────────

    /// Search field and how the query affects the strip.
    property QtObject search: QtObject {
        /// Show the search field and enable Ctrl+F.
        ///
        /// When false, the field is hidden and
        /// the other search settings are ignored.
        property bool enabled: true

        /// How the strip responds to a query.
        ///
        /// Possible values:
        ///   "scroll"  jump to the best match as you type
        ///   "filter"  hide wallpapers that do not match
        ///
        /// Invalid values raise an error and block applying.
        property string mode: "scroll"

        /// Height of the search field, in logical pixels.
        ///
        /// The font, padding and corner radius follow this height, so the
        /// field stays proportional when it is resized.
        property int fieldHeight: 44

        /// Width of the search field, in logical pixels.
        ///
        /// The field uses this width when there is room and shrinks on
        /// narrower screens.
        property int fieldWidth: 400

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

        /// Distance from the chosen screen edges as a fraction of the monitor
        /// height.
        ///
        /// Example: 0.01 = 1% of the monitor height.
        property real marginRatio: 0.01

        /// Opacity of the search field when it is not being edited.
        ///
        /// Example: 0 - fully transparent 1 - fully opaque.
        property real unfocusedOpacity: 1

        /// Animation time for search jumps, in milliseconds.
        ///
        /// Example: 800 = 0.8 seconds, 0 = instant.
        property int animationDuration: 800
    }
}
