import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Generates and caches wider, higher-resolution previews for the focused
 * wallpaper.
 *
 * Requests are processed one at a time by scripts/preview-thumb.sh. `urls`
 * maps wallpaper paths to preview file URLs for the current preview size;
 * reassigning it triggers the strip's bindings.
 */
Item {
    id: root

    // Logic-only item: it owns the Process but draws nothing.
    visible: false
    width: 0
    height: 0

    // Path -> preview file URL for the current preview size.
    property var urls: ({})

    // Paths that failed for the current size; not retried this session.
    property var failed: ({})

    property var queue: []
    property bool running: false

    property string _currentPath: ""
    property string _currentOut: ""
    property string _requestKey: ""
    property int _exitCode: -1

    readonly property bool previewsEnabled: Config.previews.enabled

    readonly property int previewHeight: Config.previews.pixelHeight
    readonly property int previewWidth: Config.previews.pixelWidth
    readonly property string configKey:
        root.previewWidth + "x" + root.previewHeight

    readonly property string script:
        Quickshell.shellPath("scripts/preview-thumb.sh")

    function isReady(path) {
        return root.urls[path] !== undefined;
    }

    // Add a preview path reported by the scan. `url` is already a file URL.
    function seed(path, url) {
        if (!path || !url || root.isReady(path))
            return;

        const next = Object.assign({}, root.urls);
        next[path] = url;
        root.urls = next;
    }

    function request(path) {
        if (!root.previewsEnabled || !path)
            return;
        if (root.isReady(path) || root.failed[path] === true)
            return;
        if (path === root._currentPath || root.queue.indexOf(path) >= 0)
            return;

        root.queue = root.queue.concat([path]);
        root._startNext();
    }

    function clearQueue() {
        root.queue = [];
    }

    function _startNext() {
        if (root.running || root.queue.length === 0)
            return;

        const path = root.queue[0];
        root.queue = root.queue.slice(1);
        root._currentPath = path;
        root._currentOut = "";
        root._requestKey = root.configKey;
        root._exitCode = -1;
        root.running = true;

        proc.command = [
            "bash", root.script,
            path,
            Config.previews.cacheDir,
            String(root.previewWidth),
            String(root.previewHeight)
        ];
        proc.running = true;
    }

    function _finish() {
        if (!root.running)
            return;

        const path = root._currentPath;
        const out = root._currentOut;

        // Discard a result produced for a previous preview size.
        if (root._requestKey === root.configKey) {
            if (root._exitCode === 0 && out !== "") {
                const next = Object.assign({}, root.urls);
                next[path] = root.toFileUrl(out);
                root.urls = next;
            } else if (root._exitCode !== 0) {
                const next = Object.assign({}, root.failed);
                next[path] = true;
                root.failed = next;
            }
        }

        root.running = false;
        root._currentPath = "";
        root._currentOut = "";
        root._requestKey = "";
        root._exitCode = -1;
        root._startNext();
    }

    function toFileUrl(path) {
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }

    onConfigKeyChanged: {
        root.urls = ({});
        root.failed = ({});
        root.queue = [];
    }

    Process {
        id: proc

        stdout: SplitParser {
            onRead: line => {
                if (line !== "")
                    root._currentOut = line;
            }
        }

        onStarted: root._exitCode = -1

        onExited: (code, status) => {
            root._exitCode = code;
        }

        onRunningChanged: {
            if (!proc.running)
                Qt.callLater(root._finish);
        }
    }
}
