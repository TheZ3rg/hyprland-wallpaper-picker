pragma Singleton

import QtQuick
import Quickshell

/// User-facing settings. Every tunable of the picker lives here.
Singleton {
    id: root

    // ── Source ────────────────────────────────────────────────

    /// Folder scanned for wallpapers. Scanning is non-recursive. Must be an
    /// absolute path; `~` is not expanded.
    property string wallpaperDir: Quickshell.env("HOME") + "/Pictures/wallpapers"

    /// Lower-case extensions without a dot. GIFs are animated on the desktop
    /// by awww and also get animated previews in the picker.
    property var extensions: ["jpg", "jpeg", "png", "webp", "gif"]

    // ── Live wallpapers ───────────────────────────────────────

    /// Video wallpapers are played by mpvpaper; images and GIFs keep using
    /// awww. Disable this to scan and apply only still wallpapers.
    property QtObject live: QtObject {
        property bool enabled: true

        /// Lower-case video extensions without a dot.
        property var extensions: ["mp4", "webm", "mkv", "mov", "m4v"]

        /// Seconds into the video used for its still thumbnail. Falls back to
        /// the first frame when the video is shorter.
        property real posterSeek: 1.0

        /// Show a LIVE badge on tiles whose wallpaper animates on the desktop.
        property bool showBadge: true

        /// Layer-shell layer for mpvpaper. "bottom" sits above awww's
        /// background surface and below normal windows. Unknown values fall
        /// back to "background".
        property string layer: "bottom"

        /// Extra mpv options appended to "no-audio loop". For example
        /// "hwdec=auto-safe" enables hardware decoding.
        property string mpvOptions: ""

        /// Pause the video while a fullscreen window hides it (mpvpaper
        /// --auto-pause). Reduces CPU use.
        property bool pauseWhenHidden: false

        /// Also pause when a fullscreen or maximized window is open: ""
        /// disables it, "full" or "max" only apply with pauseWhenHidden.
        property string autoPauseMode: ""

        /// Short muted clips shown in the focused tile. When disabled, videos
        /// and GIFs still get a static focused crop during the scan.
        property QtObject previews: QtObject {
            property bool enabled: true

            /// Clip length in milliseconds.
            property int duration: 2500

            /// Clip frame rate.
            property int fps: 12

            /// Clip width in pixels; the height follows the focused crop
            /// aspect (previews.aspectRatio * strip.focusWidthScale).
            property int width: 420

            /// WebP encoder quality, 0..100.
            property int quality: 60
        }
    }

    // ── Thumbnails and focused previews ───────────────────────

    property QtObject thumbnails: QtObject {
        /// "cover" crops every image to width x height; "preserve" keeps its
        /// own aspect ratio and shrinks it to fit inside that box.
        property string mode: "cover"

        /// Maximum thumbnail size. "preserve" thumbnails are often smaller;
        /// the real dimensions are read back by sync-thumbs.sh.
        property int width: 340
        property int height: 800

        /// Rounded corners are baked into the cached thumbnail, so changing
        /// this value regenerates the cache. 0 leaves rectangular corners.
        property int cornerRadius: 0

        /// Cache location. Safe to delete; it is rebuilt on the next scan.
        property string cacheDir: Quickshell.env("HOME") + "/.cache/qs-wallpaper-picker"

        /// Per-thumbnail fade-in after decoding, in milliseconds; 0 disables it.
        property int fadeInDuration: 800
    }

    property QtObject previews: QtObject {
        /// Generate a wider, higher-resolution crop for the focused tile.
        property bool enabled: true

        /// Width/height ratio of the focused crop. 0.8 = 4:5, 0.75 = 3:4,
        /// 1.0 = square, 1.33 = 4:3. focusWidthScale multiplies this.
        property real aspectRatio: 0.8

        /// Preview height in pixels; the width follows aspectRatio. Keep it
        /// at least as tall as the focused card to avoid upscaling.
        property int height: 1000

        /// Duration of the focused card's widening, in milliseconds;
        /// 0 makes it instant.
        property int expandDuration: 240

        /// Start the widen this many milliseconds before a long scroll ends,
        /// so the two animations overlap. The lead never exceeds
        /// expandDuration. 0 waits for the scroll to finish.
        property int expandOverlap: 250

        /// Kept separate from thumbnails so the scan prune leaves it alone.
        property string cacheDir: root.thumbnails.cacheDir + "/previews"
    }

    // ── Strip and coverflow ───────────────────────────────────

    property QtObject strip: QtObject {
        /// Height of the centred tile as a fraction of the screen height. All
        /// other tile sizes are derived from it.
        property real itemHeightRatio: 0.28

        /// Tiles farther than this many slots from the selection are unloaded.
        property int visibleRange: 30

        /// "off" stops at the ends. "endless" wraps seamlessly, duplicating
        /// wallpapers when the folder is smaller than the window. "jump"
        /// wraps instantly from one end to the other without duplicates.
        // TODO: fix the "jump" mode
        property string loopMode: "endless"

        /// Gap between tiles in pixels. Unlike the tile sizes, it does not
        /// scale with the screen or with the focused tile.
        property int spacing: 8

        /// Duration of one-step selection moves (arrows, wheel, trackpad) in
        /// milliseconds; 0 makes them instant.
        property int selectionDuration: 500

        /// Duration of long scrolls to a distant wallpaper when the picker
        /// opens, in milliseconds; 0 makes them instant. A long scroll slides
        /// the window through the collection instead of instantiating all of it.
        property int scrollDuration: 800

        /// Enable the coverflow scale falloff toward the strip edges.
        property bool coverflowEnabled: true

        /// Scale of the centred tile and of tiles falloffRange slots away.
        property real centerScale: 1.4
        property real edgeScale: 0.6

        /// Distance in tiles over which the scale falls off.
        property real falloffRange: 9.0

        /// Extra size multipliers for the focused tile.
        /// focusWidthScale multiplies the wider preview crop's aspect
        /// (previews.aspectRatio); focusHeightScale makes the focused tile
        /// taller. The wider card and the neighbour spread appear once the
        /// preview is ready. 1 = unchanged.
        property real focusWidthScale: 1.3
        property real focusHeightScale: 1.0
    }

    // ── Overlay window ────────────────────────────────────────

    property QtObject window: QtObject {
        /// Layer-shell layer of the picker overlay: "background", "bottom",
        /// "top" or "overlay". "overlay" covers panels and bars (including
        /// status bars that use the overlay layer); "top" leaves such bars
        /// above the picker. "bottom" and "background" place the picker under
        /// normal windows and are rarely useful. Unknown values fall back to
        /// "overlay".
        property string layer: "overlay"

        /// Darkness of the overlay over the live desktop, 0..1. The desktop is
        /// blurred by a Hyprland layer rule on this window's namespace; blur
        /// strength is a compositor setting, not a picker setting.
        property real backgroundDim: 0.2

        /// Show informational messages at the bottom of the overlay: scan and
        /// apply progress, search match counts and the empty-folder hint.
        /// Errors are always shown; disable this to keep the overlay quiet.
        property bool showInfoNotifications: true
    }

    // ── Search ────────────────────────────────────────────────

    property QtObject search: QtObject {
        /// How the strip responds to the query.
        /// "scroll" jumps to the best match on every keystroke;
        /// "filter" hides wallpapers that do not match.
        property string mode: "scroll"

        /// Horizontal anchor of the search field: "left", "center" or
        /// "right". Any other value falls back to "center".
        property string horizontalAlignment: "center"

        /// Vertical anchor of the search field: "top", "center" or "bottom".
        /// Any other value falls back to "top".
        property string verticalAlignment: "bottom"

        /// Distance between the search field and the anchored screen edges.
        property int margin: 15

        /// Opacity of the search field while it is not being edited.
        property real unfocusedOpacity: 0.8

        /// Duration of scroll-mode search jumps in milliseconds; 0 makes them
        /// instant. Short jumps still use strip.selectionDuration.
        property int animationDuration: 800
    }

    // ── Apply and quit ────────────────────────────────────────

    property QtObject apply: QtObject {
        /// Quit the picker after a wallpaper has been applied successfully.
        property bool closeOnApply: true

        /// "none" is instant, "grow" expands from the centre, "wipe" sweeps
        /// across (see transitionAngle), "fade" cross-fades, and "wave" is a
        /// wavy wipe.
        property string transitionType: "grow"

        /// Transition duration in milliseconds; ignored for "none".
        property int transitionDuration: 1600

        /// Transition frame rate.
        property int transitionFps: 120

        /// Wipe angle in degrees; 0 sweeps right-to-left, 90 top-to-bottom.
        property int transitionAngle: 30

        /// "cover" fills the screen and crops the overflow, "contain" fits
        /// the whole image inside it, and "fill" stretches it.
        property string resize: "fill"

        /// Scaling filter: Nearest, Bilinear, CatmullRom, Mitchell or
        /// Lanczos3. Lanczos3 is a good default; slower filters delay large
        /// images.
        property string filter: "Lanczos3"
    }
}
