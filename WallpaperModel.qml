import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Scans Config.wallpaperDir and exposes the wallpapers as `items`.
 *
 * The heavy lifting (finding files + generating cached thumbnails) is done by
 * scripts/sync-thumbs.sh, which prints a manifest the model parses. Items are
 * collected into a buffer and published once, so the strip is not rebuilt for
 * every single line.
 */
Item {
    id: root

    // Invisible logic-only component: owns the Process below, draws nothing.
    visible: false
    width: 0
    height: 0

    // Published wallpapers, one object per file:
    //   path   - real file path (used by awww)
    //   source - file:// URL of the original
    //   thumb  - file:// URL of the cached thumbnail
    //   aspect - thumbnail width / height
    property var items: []

    // True while sync-thumbs.sh is running.
    property bool scanning: false

    // True once a scan has finished; the UI waits for this before enabling
    // Enter, so it cannot act on an empty list.
    property bool ready: false

    // Last scan error, if any.
    property string error: ""

    // Emitted after a finished scan has published `items`.
    signal loaded()

    // Absolute path of the helper script (resolved against the Quickshell
    // project, not the current working directory).
    readonly property string script: Quickshell.shellPath("scripts/sync-thumbs.sh")

    // Manifest rows are collected here while the script runs, then assigned to
    // `items` in one go so the strip is rebuilt only once per scan.
    property var _buffer: []

    function rescan() {
        // Drop the previous result so the UI does not keep showing wallpapers
        // that may no longer exist.
        root._buffer = [];
        root.items = [];
        root.ready = false;
        root.error = "";
        root.scanning = true;

        // Restart even if a scan is already in flight.
        proc.running = false;
        proc.running = true;
    }

    // Calls sync-thumbs.sh and parses its tab-separated manifest from stdout.
    Process {
        id: proc
        command: [
            "bash", root.script,
            Config.wallpaperDir,          // folder to scan
            Config.thumbnails.cacheDir,   // where thumbnails are cached
            Config.thumbnails.mode,       // cover | preserve
            String(Config.thumbnails.width),
            String(Config.thumbnails.height),
            Config.extensions.join(","),  // e.g. "jpg,png,webp"
            String(Config.thumbnails.cornerRadius)
        ]

        // One manifest row per wallpaper:
        //   <sourcePath> \t <thumbPath> \t <width> \t <height>
        stdout: SplitParser {
            onRead: line => {
                // Ignore blank lines and anything that is not a manifest row.
                const parts = line.split("\t");
                if (parts.length < 2 || parts[0] === "")
                    return;

                // Dimensions describe the thumbnail. `preserve` mode returns
                // each image's own size; the fallback covers a failed convert.
                const w = parseFloat(parts[2]) || Config.thumbnails.width;
                const h = parseFloat(parts[3]) || Config.thumbnails.height;
                root._buffer.push({
                    path: parts[0],
                    // QML Image wants URLs; encodeURI escapes spaces etc.
                    source: "file://" + encodeURI(parts[0]),
                    thumb: "file://" + encodeURI(parts[1]),
                    // Sensible portrait fallback when dimensions are unknown.
                    aspect: (h > 0) ? (w / h) : 0.7
                });
            }
        }

        onStarted: root.scanning = true

        // `running` becomes false when the script exits (success or not).
        // Publish the buffered rows once here, not on every line.
        onRunningChanged: {
            if (!proc.running) {
                root.items = root._buffer;
                root.scanning = false;
                root.ready = true;
                root.loaded();
            }
        }

        // Non-zero exit codes are reported, but rows already printed are still
        // published above: partial results are better than none.
        onExited: (code, status) => {
            if (code !== 0)
                root.error = "scan failed (" + code + ")";
        }
    }

    // Re-scan when the wallpaper folder changes at runtime.
    Connections {
        target: Config
        function onWallpaperDirChanged() { root.rescan() }
    }

    // Initial scan when the picker process starts.
    Component.onCompleted: rescan()
}
