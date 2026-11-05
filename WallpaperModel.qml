import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Scans Config.wallpaperDir and exposes the wallpapers as `items`.
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

    // One object per wallpaper: { path, source, thumb, aspect }.
    property var items: []

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

    // Rows are buffered so `items` is assigned once per scan instead of
    // rebuilding the strip for every line.
    property var _buffer: []

    function rescan() {
        // Drop stale entries immediately: those files may no longer exist.
        root._buffer = [];
        root.items = [];
        root.ready = false;
        root.error = "";
        root._stderr = "";
        root.scanning = true;

        // Restart even if a scan is already in flight.
        proc.running = false;
        proc.running = true;
    }

    Process {
        id: proc
        // Positional arguments must match scripts/sync-thumbs.sh.
        command: [
            "bash", root.script,
            Config.wallpaperDir,
            Config.thumbnails.cacheDir,
            Config.thumbnails.mode,
            String(Config.thumbnails.width),
            String(Config.thumbnails.height),
            Config.extensions.join(","),
            String(Config.thumbnails.cornerRadius)
        ]

        // Manifest row: <sourcePath> \t <thumbPath> \t <width> \t <height>
        stdout: SplitParser {
            onRead: line => {
                const parts = line.split("\t");
                if (parts.length < 2 || parts[0] === "")
                    return;

                // Dimensions describe the thumbnail. They are missing only if
                // ImageMagick failed, so fall back to the requested box size.
                const w = parseFloat(parts[2]) || Config.thumbnails.width;
                const h = parseFloat(parts[3]) || Config.thumbnails.height;
                root._buffer.push({
                    path: parts[0],
                    source: "file://" + encodeURI(parts[0]),
                    thumb: "file://" + encodeURI(parts[1]),
                    aspect: (h > 0) ? (w / h) : 0.7
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
            if (!proc.running) {
                root.items = root._buffer;
                root.scanning = false;
                root.ready = true;
                root.loaded();
            }
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
        target: Config
        function onWallpaperDirChanged() { root.rescan() }
    }

    Component.onCompleted: rescan()
}
