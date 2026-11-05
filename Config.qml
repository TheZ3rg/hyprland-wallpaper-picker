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

        /// Gap between tiles as a fraction of the base tile height.
        property real spacingRatio: 0.02
    }

    /// Darkness of the overlay over the live desktop, 0..1. The desktop is
    /// blurred by a Hyprland layer rule on this window's namespace; blur
    /// strength is a compositor setting, not a picker setting.
    property real backgroundDim: 0.2

    /// Selection animation in milliseconds; 0 makes it instant.
    property int animationDuration: 500

    /// Per-thumbnail fade-in after decoding, in milliseconds; 0 disables it.
    property int thumbnailFadeInDuration: 800

    /// Quit the picker after a wallpaper has been applied successfully.
    property bool closeOnApply: true

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
