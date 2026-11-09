pragma Singleton

import QtQuick
import Quickshell

/// User-facing settings. Every tunable of the picker lives here.
Singleton {
    id: root

    /// Folder scanned for wallpapers. Scanning is non-recursive. Must be an
    /// absolute path; `~` is not expanded.
    property string wallpaperDir: Quickshell.env("HOME") + "/Pictures/wallpapers"

    /// Lower-case extensions without a dot.
    ///
    /// GIFs work, but the first apply and thumbnail generation are slow, and
    /// awww's cache can exceed 100 MB per GIF. Prefer static images.
    property var extensions: ["jpg", "jpeg", "png", "webp", "gif"]

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
    }

    /// Height of the centred tile as a fraction of the screen height. All
    /// other tile sizes and gaps are derived from it.
    property real itemHeightRatio: 0.28

    /// Tiles farther than this many slots from the selection are unloaded.
    property int visibleRange: 24

    property QtObject coverflow: QtObject {
        property bool enabled: true

        /// Scale of the centred tile and of tiles falloffRange slots away.
        property real centerScale: 1.4
        property real edgeScale: 0.6

        /// Distance in tiles over which the scale falls off.
        property real falloffRange: 9.0

        /// Extra width and height multipliers for the focused tile only.
        /// They apply on top of the coverflow scale, do not reflow the strip
        /// and let the enlarged tile overlap its neighbours. 1 = unchanged.
        property real focusedWidthScale: 1.0
        property real focusedHeightScale: 1.0

        /// Gap between tiles as a fraction of the base tile height.
        property real spacingRatio: 0.02
    }

    /// Darkness of the overlay over the live desktop, 0..1. The desktop is
    /// blurred by a Hyprland layer rule on this window's namespace; blur
    /// strength is a compositor setting, not a picker setting.
    property real backgroundDim: 0.2

    /// Layer-shell layer of the picker overlay: "background", "bottom", "top"
    /// or "overlay". "overlay" covers panels and bars (including status bars
    /// that use the overlay layer); "top" leaves such bars above the picker.
    /// "bottom" and "background" place the picker under normal windows and are
    /// rarely useful. Unknown values fall back to "overlay".
    property string layer: "overlay"

    /// Duration of one-step selection moves (arrows, wheel, trackpad) in
    /// milliseconds; 0 makes them instant.
    property int selectionAnimationDuration: 500

    /// Duration of long scrolls to a distant wallpaper when the picker opens,
    /// in milliseconds; 0 makes them instant. A long scroll slides the window
    /// through the collection instead of instantiating all of it.
    property int scrollAnimationDuration: 800

    /// Duration of scroll-mode search jumps in milliseconds; 0 makes them
    /// instant. Short jumps still use selectionAnimationDuration.
    property int searchAnimationDuration: 800

    /// Per-thumbnail fade-in after decoding, in milliseconds; 0 disables it.
    property int thumbnailFadeInDuration: 800

    /// Quit the picker after a wallpaper has been applied successfully.
    property bool closeOnApply: true

    /// Show informational messages at the bottom of the overlay: scan and
    /// apply progress, search match counts and the empty-folder hint. Errors
    /// are always shown; disable this to keep the overlay quiet.
    property bool showInfoNotifications: true

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
        property string verticalAlignment: "top"

        /// Distance between the search field and the anchored screen edges.
        property int margin: 32

        /// Opacity of the search field while it is not being edited.
        property real unfocusedOpacity: 0.45
    }

    property QtObject apply: QtObject {
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
