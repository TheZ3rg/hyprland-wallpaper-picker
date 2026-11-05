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

    // One object per wallpaper: { path, thumb, aspect }.
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

    // True while an in-flight process is being replaced. Its exit must not
    // publish the empty buffer of the interrupted scan.
    property bool _restarting: false

    function toFileUrl(path) {
        // encodeURI leaves # and ?, which QML would treat as URL syntax.
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }

    function rescan() {
        // Drop stale entries immediately: those files may no longer exist.
        root._buffer = [];
        root.items = [];
        root.ready = false;
        root.error = "";
        root._stderr = "";
        root.scanning = true;

        // Restart even if a scan is already in flight. The runningChanged
        // handler starts the replacement after the old process stops.
        root._restarting = proc.running;
        proc.running = false;
        if (!root._restarting)
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

                // Rows are only emitted for successfully generated thumbnails,
                // so dimensions are always present and describe the real file.
                const w = parseFloat(parts[2]);
                const h = parseFloat(parts[3]);
                if (!(w > 0) || !(h > 0))
                    return;

                root._buffer.push({
                    path: parts[0],
                    thumb: root.toFileUrl(parts[1]),
                    aspect: w / h
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
        target: Config
        function onWallpaperDirChanged() { root.rescan() }
    }

    Component.onCompleted: rescan()
}
