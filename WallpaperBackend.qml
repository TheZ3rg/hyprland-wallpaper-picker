import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Wraps the wallpaper programs.
 *
 * Images and GIFs are shown by awww, videos by mpvpaper. The picker reads the
 * active wallpaper back with scripts/query-wallpaper.sh and reports apply
 * failures instead of closing silently.
 */
Item {
    id: root

    // Logic-only item: it owns the Process objects and state but draws nothing.
    visible: false
    width: 0
    height: 0

    // Empty while nothing is displayed or the source is unknown.
    property string currentPath: ""

    property bool applying: false

    // True while the in-flight apply is a video.
    property bool applyingLive: false

    // True after a successful query, including a query that found no image.
    property bool queryDone: false

    property string error: ""

    signal queried()
    signal applied(string path)
    signal applyFailed(string message)

    readonly property string applyScript: Quickshell.shellPath("scripts/apply.sh")
    readonly property string applyLiveScript: Quickshell.shellPath("scripts/apply-live.sh")
    readonly property string queryScript: Quickshell.shellPath("scripts/query-wallpaper.sh")

    property string _pendingPath: ""
    property bool _pendingLive: false
    property string _applyErr: ""
    property bool _applyStarted: false

    property string _queryPath: ""

    function refresh() {
        if (queryProc.running)
            return;
        root._queryPath = "";
        root.error = "";
        queryProc.ok = false;
        queryProc.err = "";
        queryProc.running = true;
    }

    function apply(path, live) {
        if (!path || path === "" || applyProc.running)
            return;

        root.error = "";
        root._applyErr = "";
        root._pendingPath = path;
        root._pendingLive = live === true;
        root.applying = true;
        root.applyingLive = root._pendingLive;
        root._applyStarted = false;
        applyProc.command = root._pendingLive
            ? buildLiveArgs(path)
            : buildArgs(path);
        applyProc.running = true;
    }

    function buildArgs(path) {
        const a = Config.apply;
        const t = a.transition;
        const args = ["bash", root.applyScript, path];

        args.push("--resize", resizeMode(a.resize));
        // awww crops from the top-left by default; centre is the useful
        // default for wallpapers.
        if (a.resize === "cover")
            args.push("--crop-gravity", "center");
        args.push("--filter", a.filter);
        args.push("--transition-type", transitionType(t.type));

        if (t.type === "grow")
            args.push("--transition-pos", "center");
        if (t.type === "wipe")
            args.push("--transition-angle", String(t.angle));
        if (t.type !== "none") {
            // Config uses milliseconds; awww uses seconds.
            args.push("--transition-duration", String(Math.max(0.01, t.duration / 1000)));
            args.push("--transition-fps", String(Math.max(1, t.fps)));
        }
        return args;
    }

    function buildLiveArgs(path) {
        const a = Config.live;
        const args = ["bash", root.applyLiveScript, path,
                      "--layer", liveLayer(a.layer),
                      "--mpv-options", String(a.mpvOptions ?? "").trim()];

        if (a.pauseWhenHidden) {
            args.push("--auto-pause");
            const mode = autoPauseMode(a.autoPauseMode);
            if (mode !== "")
                args.push("--auto-mode", mode);
        }
        return args;
    }

    function liveLayer(v) {
        switch (v) {
        case "background":
        case "bottom":
        case "top":
        case "overlay":
            return v;
        default:
            return "background";
        }
    }

    function autoPauseMode(v) {
        switch (v) {
        case "full":
            return "FULL";
        case "max":
            return "MAX";
        default:
            return "";
        }
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

    Process {
        id: queryProc
        // A shell wrapper makes a missing binary produce a normal exit code
        // and stderr instead of a Process that never starts.
        command: ["bash", root.queryScript]

        property string err: ""
        property bool ok: false

        stdout: SplitParser {
            onRead: line => {
                const tab = line.indexOf("\t");
                if (tab < 0)
                    return;
                root._queryPath = line.slice(tab + 1);
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
            root.currentPath = root._queryPath;
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
                    : "wallpaper query failed (" + code + ")";
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
                root.applyingLive = false;
                root._pendingPath = "";
                root.error = "could not start the apply script";
                root.applyFailed(root.error);
            }
        }

        onExited: (code, status) => {
            const path = root._pendingPath;
            const live = root._pendingLive;
            const message = root._applyErr !== ""
                ? root._applyErr
                : (live ? "mpvpaper" : "awww img") + " failed (" + code + ")";

            root.applying = false;
            root.applyingLive = false;
            root._pendingPath = "";
            root._pendingLive = false;
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
