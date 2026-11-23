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
        const dirs = Config.source.dirs;
        if (!Array.isArray(dirs) || dirs.length === 0) {
            out.push("source.dirs: must be a non-empty list of absolute paths");
        } else {
            for (let i = 0; i < dirs.length; ++i) {
                const dir = dirs[i];
                const path = "source.dirs[" + i + "]";
                if (typeof dir !== "string" || dir === "")
                    out.push(path + ": must be a non-empty absolute path");
                else if (!dir.startsWith("/"))
                    out.push(path + ": must be an absolute path: \"" + dir + "\"");
            }
        }

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
        between(out, "thumbnails.quality", Config.thumbnails.quality, 1, 100);
        nonNegative(out, "thumbnails.fadeInDuration",
            Config.thumbnails.fadeInDuration);
        nonNegative(out, "thumbnails.videoPosterSeek",
            Config.thumbnails.videoPosterSeek);
        nonNegative(out, "thumbnails.workers",
            Config.thumbnails.workers);

        // Previews
        positive(out, "previews.widthScale", Config.previews.widthScale);
        positive(out, "previews.heightScale", Config.previews.heightScale);
        between(out, "previews.quality", Config.previews.quality, 1, 100);

        // Strip
        nonNegative(out, "strip.spacingRatio", Config.strip.spacingRatio);
        nonNegative(out, "strip.moveAnimationDuration",
            Config.strip.moveAnimationDuration);
        nonNegative(out, "strip.openAnimationDuration",
            Config.strip.openAnimationDuration);
        positive(out, "strip.coverflow.centerScale",
            Config.strip.coverflow.centerScale);
        positive(out, "strip.coverflow.edgeScale",
            Config.strip.coverflow.edgeScale);
        positive(out, "strip.coverflow.falloffRange",
            Config.strip.coverflow.falloffRange);
        positive(out, "strip.liveBadgeFontSize",
            Config.strip.liveBadgeFontSize);

        // Overlay
        oneOf(out, "overlay.layer", Config.overlay.layer,
            ["background", "bottom", "top", "overlay"]);
        between(out, "overlay.backgroundDim", Config.overlay.backgroundDim,
            0, 1);
        positive(out, "overlay.statusFontSize",
            Config.overlay.statusFontSize);

        // Search
        oneOf(out, "search.mode", Config.search.mode, ["scroll", "filter"]);
        positive(out, "search.fieldHeight", Config.search.fieldHeight);
        positive(out, "search.fieldWidth", Config.search.fieldWidth);
        oneOf(out, "search.horizontalAlignment",
            Config.search.horizontalAlignment, ["left", "center", "right"]);
        oneOf(out, "search.verticalAlignment",
            Config.search.verticalAlignment, ["top", "center", "bottom"]);
        nonNegative(out, "search.marginRatio", Config.search.marginRatio);
        between(out, "search.unfocusedOpacity",
            Config.search.unfocusedOpacity, 0, 1);
        nonNegative(out, "search.animationDuration",
            Config.search.animationDuration);

        return out;
    }
}
