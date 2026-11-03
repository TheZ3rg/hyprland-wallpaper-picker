import QtQuick
import Quickshell
import Quickshell.Io
import qs

/**
 * Thin wrapper around the awww CLI.
 *
 * awww has no config file: it caches the last displayed image and restores it
 * when its daemon starts, so there is nothing to persist here.
 *
 *   currentPath - the wallpaper awww is currently displaying, read from
 *                 `awww query` (empty when the daemon shows a plain colour).
 *   apply(path) - hand a new image to the daemon and play the configured
 *                 transition. Fire-and-forget: `awww img` returns as soon as
 *                 the daemon has accepted the request.
 */
Item {
    id: root

    // Invisible logic-only component: holds the Process and state below; it
    // draws nothing.
    visible: false
    width: 0
    height: 0

    // Wallpaper awww reports as displayed. Empty means unknown: the daemon is
    // not running yet, or it is showing a plain colour.
    property string currentPath: ""

    // True while `awww query` is running; prevents overlapping queries.
    property bool querying: false

    // Last error message, if any.
    property string error: ""

    // Emitted right after an apply request has been handed to awww.
    signal applied(string path)

    // Helper script that starts the daemon if needed and calls `awww img`.
    readonly property string applyScript: Quickshell.shellPath("scripts/apply.sh")

    // Ask the daemon which wallpaper it currently displays.
    function refresh() {
        if (queryProc.running)
            return; // a query is already in flight
        queryProc.buf = "";
        root.error = "";
        queryProc.running = true;
    }

    // Apply a wallpaper. Fire-and-forget: the daemon owns the transition and
    // `awww img` returns as soon as the request is accepted.
    function apply(path) {
        if (!path || path === "")
            return;
        Quickshell.execDetached(buildArgs(path));
        root.error = "";
        // Optimistic update so the UI can react immediately; the query below
        // reconciles this with what the daemon actually shows.
        root.currentPath = path;
        root.applied(path);
        // Give awww a moment to update its state, then verify.
        refreshTimer.restart();
    }

    /// Builds `bash apply.sh <path> <awww img options...>`, translating the
    /// friendly Config values into awww's vocabulary.
    function buildArgs(path) {
        const a = Config.apply;
        const args = ["bash", root.applyScript, path];

        // Map Config's friendly names to awww's vocabulary.
        args.push("--resize", resizeMode(a.resize));
        // "cover" needs a gravity; awww's default is top-left, we want centre.
        if (a.resize === "cover")
            args.push("--crop-gravity", "center");
        args.push("--filter", a.filter);
        args.push("--transition-type", transitionType(a.transitionType));

        // Transition-specific options. "none" accepts no duration/fps.
        if (a.transitionType === "grow")
            args.push("--transition-pos", "center");
        if (a.transitionType === "wipe")
            args.push("--transition-angle", String(a.transitionAngle));
        if (a.transitionType !== "none") {
            // Config stores milliseconds; awww wants seconds.
            args.push("--transition-duration", String(Math.max(0.01, a.transitionDuration / 1000)));
            args.push("--transition-fps", String(Math.max(1, a.transitionFps)));
        }
        return args;
    }

    // Config.resize -> awww's --resize values.
    function resizeMode(v) {
        switch (v) {
        case "cover":   return "crop";
        case "contain": return "fit";
        case "fill":    return "stretch";
        default:        return "crop";
        }
    }

    // Config.apply.transitionType -> awww's --transition-type values.
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

    // One-shot `awww query`; its output is parsed into currentPath.
    Process {
        id: queryProc
        command: ["awww", "query"]

        // First image path found in stdout. Cleared before each query.
        property string buf: ""

        stdout: SplitParser {
            onRead: line => {
                // ": DP-2: 2560x1440, scale: 1, currently displaying: image: /path"
                // awww prints one line per output; keep the first image path.
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
            // Process has ended; publish whatever was parsed (may be empty).
            root.currentPath = queryProc.buf;
        }
        onExited: (code, status) => {
            if (code === 127) // shell could not find the awww binary
                root.error = "awww not found";
            else if (code !== 0)
                root.error = "awww query failed (" + code + ")";
        }
    }

    // Debounce: restarting on every apply means the query runs once, after the
    // last apply request has settled.
    Timer {
        id: refreshTimer
        interval: 500
        onTriggered: root.refresh()
    }

    // Populate currentPath as soon as the picker starts.
    Component.onCompleted: refresh()
}
