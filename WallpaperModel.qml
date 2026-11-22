import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Scans Config.source.dirs and exposes the wallpapers as `items`.
 *
 * File discovery and thumbnail generation happen in scripts/sync-thumbs.sh,
 * which prints a tab-separated manifest parsed here.
 */
Item {
    id: root

    // Logic-only item: it owns the Process below but draws nothing.
    visible: false
    width: 0
    height: 0

    // One object per wallpaper:
    // { path, source, thumb, aspect, preview, live, video, gif }.
    property var items: []

    // Logical height of the largest connected screen. Cache sizes follow it,
    // so moving the picker between monitors does not regenerate anything. The
    // picker scales the images down on smaller screens.
    readonly property int generationHeight: {
        let h = 0;
        for (let i = 0; i < Quickshell.screens.length; ++i)
            h = Math.max(h, Quickshell.screens[i].height);
        return h;
    }

    // Height the current scan was generated for. It prevents a rescan while
    // the same screens are connected.
    property int _scannedHeight: 0

    property bool scanning: false

    // False until a scan has completed. The picker uses it to disable Enter,
    // so it cannot act on an empty list during the initial scan.
    property bool ready: false

    property string error: ""

    // Last non-empty stderr line from sync-thumbs.sh. It is promoted to
    // `error` when the script fails.
    property string _stderr: ""

    signal loaded()

    readonly property string script: Quickshell.shellPath("scripts/sync-thumbs.sh")

    // Newline-separated source list for scripts/sync-thumbs.sh.
    readonly property string _sourceDirs:
        Array.isArray(Config.source.dirs)
            ? Config.source.dirs.join("\n")
            : ""

    // Thumbnail size derived from the configured ratios and the largest
    // connected screen.
    readonly property int thumbHeight:
        Math.max(1, Math.round(root.generationHeight
            * Config.thumbnails.heightRatio))
    readonly property int thumbWidth:
        Math.max(1, Math.round(root.generationHeight
            * Config.thumbnails.widthRatio))

    // Preview size is a multiple of the thumbnail size. Center width scaling
    // applies only in coverflow mode.
    readonly property real previewAspect:
        Math.max(0.05,
            (Config.thumbnails.widthRatio * Config.previews.widthScale)
            / Math.max(0.001,
                Config.thumbnails.heightRatio * Config.previews.heightScale))
    readonly property int previewHeight:
        Math.max(1, Math.round(thumbHeight * Config.previews.heightScale))
    readonly property int previewWidth:
        Math.max(1, Math.round(previewHeight * previewAspect))

    // Rows are buffered so `items` is assigned once per scan instead of
    // rebuilding the strip for every line.
    property var _buffer: []

    // True while an in-flight process is being replaced. Its exit must not
    // publish the empty buffer of the interrupted scan.
    property bool _restarting: false

    function toFileUrl(path) {
        // encodeURI leaves # and ?, which QML would treat as URL syntax.
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }

    function beginScan() {
        if (root.generationHeight <= 0
                || root._scannedHeight === root.generationHeight)
            return;
        root._scannedHeight = root.generationHeight;
        root.rescan();
    }

    function rescan() {
        if (root.generationHeight <= 0)
            return;

        // Drop stale entries immediately: those files may no longer exist.
        root._buffer = [];
        root.items = [];
        root.ready = false;
        root.error = "";
        root._stderr = "";
        root.scanning = true;

        // Restart even if a scan is already in flight. The runningChanged
        // handler starts the replacement after the old process stops.
        if (proc.running) {
            root._restarting = true;
            proc.running = false;
        } else {
            proc.running = true;
        }
    }

    Process {
        id: proc
        // Positional arguments must match scripts/sync-thumbs.sh.
        command: [
            "bash", root.script,
            root._sourceDirs,
            Config.thumbnails.cacheDir,
            String(root.thumbWidth),
            String(root.thumbHeight),
            String(Config.thumbnails.quality),
            Config.awww.extensions.join(","),
            Config.previews.enabled ? Config.previews.cacheDir : "",
            String(root.previewWidth),
            String(root.previewHeight),
            String(Config.previews.quality),
            Config.mpvpaper.enabled ? Config.mpvpaper.extensions.join(",") : "",
            String(Config.thumbnails.videoPosterSeek),
            String(Config.thumbnails.workers)
        ]

        // Manifest row:
        // <sourcePath> \t <thumbPath> \t <width> \t <height> \t <previewPath>
        // \t <kind>
        stdout: SplitParser {
            onRead: line => {
                const parts = line.split("\t");
                if (parts.length < 2 || parts[0] === "")
                    return;

                // Rows are only emitted for successfully generated thumbnails,
                // so dimensions are always present and describe the real file.
                const w = parseFloat(parts[2]);
                const h = parseFloat(parts[3]);
                if (!(w > 0) || !(h > 0))
                    return;

                const preview = parts.length > 4 ? parts[4] : "";
                const kind = parts.length > 5 ? parts[5] : "image";

                root._buffer.push({
                    path: parts[0],
                    // Original file, used for live video and GIF playback.
                    source: root.toFileUrl(parts[0]),
                    thumb: root.toFileUrl(parts[1]),
                    aspect: w / h,
                    preview: preview !== "" ? root.toFileUrl(preview) : "",
                    // Animated on the desktop: video or GIF.
                    live: kind === "video" || kind === "gif",
                    // Played by mpvpaper instead of awww.
                    video: kind === "video",
                    // Played live in the center card.
                    gif: kind === "gif"
                });
            }
        }

        stderr: SplitParser {
            onRead: line => {
                if (line !== "")
                    root._stderr = line;
            }
        }

        onStarted: root.scanning = true

        onRunningChanged: {
            if (proc.running)
                return;

            if (root._restarting) {
                root._restarting = false;
                proc.running = true;
                return;
            }

            root.items = root._buffer;
            root.scanning = false;
            root.ready = true;
            root.loaded();
        }

        // Rows printed before a failure have already been buffered, so a
        // partial result is still published above.
        onExited: (code, status) => {
            if (code !== 0)
                root.error = root._stderr !== ""
                    ? root._stderr
                    : "scan failed (" + code + ")";
        }
    }

    Connections {
        target: Config.source
        function onDirsChanged() { root.rescan() }
    }

    onGenerationHeightChanged: root.beginScan()

    Component.onCompleted: root.beginScan()
}
