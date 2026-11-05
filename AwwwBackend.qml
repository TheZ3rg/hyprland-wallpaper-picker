import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Wraps the awww CLI.
 *
 * The daemon owns the active wallpaper; the picker reads it back with
 * `awww query` and reports apply failures instead of closing silently.
 */
Item {
    id: root

    // Logic-only item: it owns the Process objects and state but draws nothing.
    visible: false
    width: 0
    height: 0

    // Empty while the daemon is not running or shows a plain colour.
    property string currentPath: ""

    property bool applying: false

    // True after a successful query, including a query that found no image.
    property bool queryDone: false

    property string error: ""

    signal queried()
    signal applied(string path)
    signal applyFailed(string message)

    readonly property string applyScript: Quickshell.shellPath("scripts/apply.sh")

    property string _pendingPath: ""
    property string _applyErr: ""
    property bool _applyStarted: false

    function refresh() {
        if (queryProc.running)
            return;
        queryProc.buf = "";
        queryProc.ok = false;
        queryProc.err = "";
        root.error = "";
        queryProc.running = true;
    }

    function apply(path) {
        if (!path || path === "" || applyProc.running)
            return;

        root.error = "";
        root._applyErr = "";
        root._pendingPath = path;
        root.applying = true;
        root._applyStarted = false;
        applyProc.command = buildArgs(path);
        applyProc.running = true;
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
        // A shell wrapper makes a missing binary produce a normal exit code
        // and stderr instead of a Process that never starts.
        command: ["bash", "-c", "exec awww query"]

        property string buf: ""
        property string err: ""
        property bool ok: false

        stdout: SplitParser {
            onRead: line => {
                // Example: ": DP-2: 2560x1440, scale: 1, currently displaying: image: /path"
                const m = line.match(/currently displaying:\s*image:\s*(.+?)\s*$/);
                if (m && queryProc.buf === "")
                    queryProc.buf = m[1];
            }
        }
        stderr: SplitParser {
            onRead: line => {
                if (line !== "")
                    queryProc.err = line;
            }
        }
        onRunningChanged: {
            if (queryProc.running)
                return;
            // Stdout may be parsed after the process has already exited. Do
            // not clear a known path on a transient query failure.
            if (!queryProc.ok)
                return;
            root.currentPath = queryProc.buf;
            root.queryDone = true;
            root.queried();
        }
        onExited: (code, status) => {
            queryProc.ok = (code === 0);
            if (code === 0)
                return;
            if (code === 127)
                root.error = "awww not found";
            else
                root.error = queryProc.err !== ""
                    ? queryProc.err
                    : "awww query failed (" + code + ")";
        }
    }

    Process {
        id: applyProc

        stderr: SplitParser {
            onRead: line => {
                if (line !== "")
                    root._applyErr = line;
            }
        }

        onStarted: root._applyStarted = true

        onRunningChanged: {
            if (applyProc.running)
                return;

            // onExited normally clears `applying` first. If it did not and
            // the process never started, report the failure here.
            if (root.applying && root._pendingPath !== "" && !root._applyStarted) {
                root.applying = false;
                root._pendingPath = "";
                root.error = "could not start apply.sh";
                root.applyFailed(root.error);
            }
        }

        onExited: (code, status) => {
            const path = root._pendingPath;
            const message = root._applyErr !== ""
                ? root._applyErr
                : "awww img failed (" + code + ")";

            root.applying = false;
            root._pendingPath = "";
            root._applyErr = "";
            root._applyStarted = false;

            if (code !== 0) {
                root.error = message;
                root.applyFailed(message);
                return;
            }

            root.error = "";
            root.currentPath = path;
            root.applied(path);
            // The daemon updates its state asynchronously, after the command
            // exits.
            refreshTimer.restart();
        }
    }

    // Restarting on every successful apply debounces the refresh until the
    // last request has settled.
    Timer {
        id: refreshTimer
        interval: 500
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()
}
