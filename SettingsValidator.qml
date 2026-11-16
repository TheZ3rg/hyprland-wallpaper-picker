import QtQuick

/**
 * Validates the user-facing values in Config.qml.
 *
 * The strip and backends still use safe fallbacks so the picker can render,
 * but invalid settings are reported in the overlay and prevent applying.
 */
Item {
    id: root

    // Logic-only item: it draws nothing.
    visible: false
    width: 0
    height: 0

    readonly property var errors: root.validate()
    readonly property bool hasErrors: root.errors.length > 0

    function formatList(allowed) {
        return allowed.map(value => "\"" + value + "\"").join(", ");
    }

    function oneOf(out, path, value, allowed) {
        if (allowed.indexOf(value) < 0)
            out.push(path + ": \"" + value + "\" is not one of "
                + root.formatList(allowed));
    }

    function positive(out, path, value) {
        if (!(value > 0))
            out.push(path + ": must be greater than 0");
    }

    function nonNegative(out, path, value) {
        if (!(value >= 0))
            out.push(path + ": must be 0 or greater");
    }

    function between(out, path, value, minimum, maximum) {
        if (!(value >= minimum && value <= maximum))
            out.push(path + ": must be between " + minimum + " and " + maximum);
    }

    function validate() {
        const out = [];

        // Source
        if (typeof Config.source.dir !== "string" || Config.source.dir === "")
            out.push("source.dir: must be a non-empty absolute path");
        else if (!Config.source.dir.startsWith("/"))
            out.push("source.dir: must be an absolute path: \""
                + Config.source.dir + "\"");

        // awww
        oneOf(out, "awww.transition.type", Config.awww.transition.type,
            ["none", "grow", "wipe", "fade", "wave"]);
        nonNegative(out, "awww.transition.duration",
            Config.awww.transition.duration);
        positive(out, "awww.transition.fps", Config.awww.transition.fps);
        oneOf(out, "awww.resize", Config.awww.resize,
            ["cover", "contain", "fill"]);
        oneOf(out, "awww.filter", Config.awww.filter,
            ["Nearest", "Bilinear", "CatmullRom", "Mitchell", "Lanczos3"]);

        // mpvpaper
        oneOf(out, "mpvpaper.layer", Config.mpvpaper.layer,
            ["background", "bottom", "top", "overlay"]);
        oneOf(out, "mpvpaper.autoPauseMode", Config.mpvpaper.autoPauseMode,
            ["", "full", "max"]);

        // Thumbnails
        positive(out, "thumbnails.widthRatio", Config.thumbnails.widthRatio);
        positive(out, "thumbnails.heightRatio", Config.thumbnails.heightRatio);
        nonNegative(out, "thumbnails.cornerRadius",
            Config.thumbnails.cornerRadius);
        nonNegative(out, "thumbnails.fadeInDuration",
            Config.thumbnails.fadeInDuration);
        nonNegative(out, "thumbnails.videoPosterSeek",
            Config.thumbnails.videoPosterSeek);

        // Previews
        positive(out, "previews.widthScale", Config.previews.widthScale);
        positive(out, "previews.heightScale", Config.previews.heightScale);
        positive(out, "previews.animated.width",
            Config.previews.animated.width);
        positive(out, "previews.animated.duration",
            Config.previews.animated.duration);
        positive(out, "previews.animated.fps", Config.previews.animated.fps);
        between(out, "previews.animated.quality",
            Config.previews.animated.quality, 1, 100);

        // Strip
        oneOf(out, "strip.loopMode", Config.strip.loopMode,
            ["endless", "off"]);
        nonNegative(out, "strip.spacing", Config.strip.spacing);
        nonNegative(out, "strip.selectionDuration",
            Config.strip.selectionDuration);
        nonNegative(out, "strip.scrollDuration", Config.strip.scrollDuration);
        positive(out, "strip.centerScale", Config.strip.centerScale);
        positive(out, "strip.edgeScale", Config.strip.edgeScale);
        positive(out, "strip.falloffRange", Config.strip.falloffRange);
        positive(out, "strip.centerWidthScale",
            Config.strip.centerWidthScale);
        positive(out, "strip.centerHeightScale",
            Config.strip.centerHeightScale);

        // Overlay
        oneOf(out, "overlay.layer", Config.overlay.layer,
            ["background", "bottom", "top", "overlay"]);
        between(out, "overlay.backgroundDim", Config.overlay.backgroundDim,
            0, 1);

        // Search
        oneOf(out, "search.mode", Config.search.mode, ["scroll", "filter"]);
        oneOf(out, "search.horizontalAlignment",
            Config.search.horizontalAlignment, ["left", "center", "right"]);
        oneOf(out, "search.verticalAlignment",
            Config.search.verticalAlignment, ["top", "center", "bottom"]);
        nonNegative(out, "search.margin", Config.search.margin);
        between(out, "search.unfocusedOpacity",
            Config.search.unfocusedOpacity, 0, 1);
        nonNegative(out, "search.animationDuration",
            Config.search.animationDuration);

        return out;
    }
}
