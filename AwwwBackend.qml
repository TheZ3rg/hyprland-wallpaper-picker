import QtQuick
import Quickshell
import Quickshell.Io
import qs

/**
 * Wraps the awww CLI.
 *
 * The daemon owns the active wallpaper; the picker only reads it back with
 * `awww query` and persists no copy of its own.
 */
Item {
    id: root

    // Logic-only item: it owns a Process and state but draws nothing.
    visible: false
    width: 0
    height: 0

    // Empty while the daemon is not running or shows a plain colour.
    property string currentPath: ""

    property bool querying: false

    property string error: ""

    signal applied(string path)

    readonly property string applyScript: Quickshell.shellPath("scripts/apply.sh")

    function refresh() {
        if (queryProc.running)
            return;
        queryProc.buf = "";
        root.error = "";
        queryProc.running = true;
    }

    function apply(path) {
        if (!path || path === "")
            return;
        Quickshell.execDetached(buildArgs(path));
        root.error = "";
        // Show the choice immediately; the query below reconciles it with the
        // daemon's actual state.
        root.currentPath = path;
        root.applied(path);
        // The daemon updates its state asynchronously, after the command exits.
        refreshTimer.restart();
    }

    function buildArgs(path) {
        const a = Config.apply;
        const args = ["bash", root.applyScript, path];

        args.push("--resize", resizeMode(a.resize));
        // awww crops from the top-left by default; centre is the useful
        // default for wallpapers.
        if (a.resize === "cover")
            args.push("--crop-gravity", "center");
        args.push("--filter", a.filter);
        args.push("--transition-type", transitionType(a.transitionType));

        if (a.transitionType === "grow")
            args.push("--transition-pos", "center");
        if (a.transitionType === "wipe")
            args.push("--transition-angle", String(a.transitionAngle));
        if (a.transitionType !== "none") {
            // Config uses milliseconds; awww uses seconds.
            args.push("--transition-duration", String(Math.max(0.01, a.transitionDuration / 1000)));
            args.push("--transition-fps", String(Math.max(1, a.transitionFps)));
        }
        return args;
    }

    // Config describes the visual result; awww names its resize algorithms.
    function resizeMode(v) {
        switch (v) {
        case "cover":   return "crop";
        case "contain": return "fit";
        case "fill":    return "stretch";
        default:        return "crop";
        }
    }

    function transitionType(v) {
        switch (v) {
        case "grow":   return "grow";
        case "wipe":   return "wipe";
        case "fade":   return "fade";
        case "wave":   return "wave";
        case "none":   return "none";
        default:       return "grow";
        }
    }

    // awww prints one line per output, and outputs may show different images.
    // The picker only needs the first image path it finds.
    Process {
        id: queryProc
        command: ["awww", "query"]

        property string buf: ""

        stdout: SplitParser {
            onRead: line => {
                // Example: ": DP-2: 2560x1440, scale: 1, currently displaying: image: /path"
                const m = line.match(/currently displaying:\s*image:\s*(.+?)\s*$/);
                if (m && queryProc.buf === "")
                    queryProc.buf = m[1];
            }
        }
        onStarted: root.querying = true
        onRunningChanged: {
            if (queryProc.running)
                return;
            root.querying = false;
            // Publish whatever was parsed; a failed query leaves it empty and
            // clears a stale path.
            root.currentPath = queryProc.buf;
        }
        onExited: (code, status) => {
            if (code === 127) // the shell could not find awww
                root.error = "awww not found";
            else if (code !== 0)
                root.error = "awww query failed (" + code + ")";
        }
    }

    // Restarting on every apply debounces the refresh until the last request
    // has settled.
    Timer {
        id: refreshTimer
        interval: 500
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()
}
