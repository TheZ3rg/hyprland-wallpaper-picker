pragma Singleton

import QtQuick
import Quickshell

/**
 * User-facing configuration for the wallpaper picker.
 */
Singleton {
    id: root

    /// ---- Wallpapers ----

    /// The folder that is scanned for wallpapers.
    property string wallpaperDir: Quickshell.env("HOME") + "/Pictures/wallpapers"

    /** File extensions (lowercase, without the dot) that count as wallpapers.
     *
     * GIFs are supported, but the first applying takes a very long time.
     * Also, cached GIFs take up a lot of disk space (could be more than 100MB per GIF).
     * -> Not recommended to use GIFs as wallpapers.
     *
     * For a full list of supported formats, see awww's documentation.
     */ 
    property var extensions: ["jpg", "jpeg", "png", "webp", "gif"]

    /// ---- Thumbnails ----

    property QtObject thumbnails: QtObject {
        /// "cover"    = crop to a fixed portrait ratio (best for coverflow)
        /// "preserve" = keep each image's own aspect ratio (letterboxed)
        property string mode: "covers"

        /// Narrow portrait strips.
        property int width: 340
        property int height: 800

        /// Rounded corners baked into the thumbnail (0 = square/rectangular).
        property int cornerRadius: 0

        /// Auto-generated thumbnail cache (safe to delete; it will be rebuilt).
        property string cacheDir: Quickshell.env("HOME") + "/.cache/qs-wallpaper-picker"
    }

    /// ---- Strip layout ----

    /// Height of the centred item, as a fraction of the screen height.
    property real itemHeightRatio: 0.28

    /// How many items are kept visible/loaded around the selection.
    property int visibleRange: 24

    /// ---- Coverflow ----

    property QtObject coverflow: QtObject {
        property bool enabled: true

        /// All that scales multiplied by the base item height (itemHeightRatio)
        
        /// Scale of the centred item / of the items at the edges.
        property real centerScale: 1.4
        property real edgeScale: 0.6

        /// Distance (in item slots) over which the scale falls off.
        property real falloffRange: 9.0

        /// Gap between items, as a fraction of the base item height.
        property real spacingRatio: 0.02
    }

    /// ---- Look ----

    /// Dim behind the strip (0..1).
    ///
    /// The backdrop itself is the *live desktop*, blurred by a Hyprland layer
    /// rule on the picker's namespace (see the README). Tune the blur strength
    /// in your Hyprland config (decoration:blur:*), not here.
    property real backgroundDim: 0.2

    /// Selection animation duration, ms (0 = instant).
    property int animationDuration: 500

    /// Fade-in duration for thumbnails as they finish decoding, ms (0 = instant).
    property int thumbnailFadeInDuration: 800

    /// ---- Behaviour ----

    /// Close the picker after applying a wallpaper.
    property bool closeOnApply: true

    /// ---- Applying (awww) ----

    property QtObject apply: QtObject {
        /// Transition played on the desktop when a wallpaper is applied:
        ///   "none"   = instant
        ///   "grow"   = reveals from the centre outward
        ///   "wipe"   = reveals from the top downward (see transitionAngle)
        ///   "fade"   = cross-fades
        ///   "wave"   = a wavy wipe
        property string transitionType: "grow"

        /// Duration in milliseconds (ignored for "none").
        property int transitionDuration: 1600

        /// Frames per second for the transition (max 255).
        property int transitionFps: 120

        /// Wipe angle in degrees (0 = right-to-left, 90 = top-to-bottom).
        property int transitionAngle: 30

        /// How the image fills the (possibly differently shaped) screen:
        ///   "cover"   = fill, cropping the overflow (default)
        ///   "contain" = fit inside, letterboxed
        ///   "fill"    = stretch to the screen
        property string resize: "fill"

        /// Resampling filter: Nearest | Bilinear | CatmullRom | Mitchell | Lanczos3
        ///
        /// For wallpapers that are smaller or bigger than the screen,
        /// this is the filter used to scale them up or down.
        /// The default is Lanczos3, which is usually the best choice for wallpapers.
        /// Not recommended to change this unless necessary.
        property string filter: "Lanczos3"
    }
}
