import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Root layer-shell window of the picker.
 *
 * It owns the full-screen overlay, keyboard shortcuts, apply/close behaviour
 * and the IPC target used by scripts/open-picker.sh.
 */
PanelWindow {
    id: root

    visible: true

    // Bind to the focused monitor, with the first output as a fallback during
    // startup or hotplug. Because this is a binding, the window follows focus
    // if another monitor is focused while the picker is open.
    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)
        ?? Quickshell.screens[0]

    // Overlay: do not reserve space or shift other windows.
    exclusionMode: ExclusionMode.Ignore

    // Transparent so the compositor-blurred desktop stays visible.
    color: "transparent"

    // Layer-shell level from Config.layer. "overlay" (the default) covers
    // panels and bars; "top" keeps bars that use the overlay layer above the
    // picker.
    WlrLayershell.layer: root.layerFor(Config.layer)

    // Must match the namespace used by Hyprland's layer rule.
    WlrLayershell.namespace: "quickshell:wallpaperPicker"

    // Shortcuts only receive keys reliably while the surface holds keyboard
    // focus.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    // Whether the initial wallpaper has been chosen. A late query result must
    // not move the strip after the user has started navigating.
    property bool _initialSelectionDone: false

    // Wallpaper selected before the current search started; clearing the
    // query returns to it when it still exists.
    property string _preSearchPath: ""
    property bool _searching: false

    function layerFor(name) {
        switch (name) {
        case "background":
            return WlrLayer.Background;
        case "bottom":
            return WlrLayer.Bottom;
        case "top":
            return WlrLayer.Top;
        case "overlay":
            return WlrLayer.Overlay;
        default:
            return WlrLayer.Overlay;
        }
    }

    AwwwBackend {
        id: awww
    }

    WallpaperModel {
        id: model
    }

    WallpaperSearch {
        id: search
        items: model.items
        query: searchField.text
        mode: Config.search.mode
    }

    SearchField {
        id: searchField
        // Above the status box, which may move out of its way.
        z: 2100
        onMovePrevious: strip.prev()
        onMoveNext: strip.next()
        onSubmitted: {
            if (model.ready)
                root.applyIndex(strip.currentIndex);
        }
        onCanceled: root.cancelSearch()
    }

    // Clicking an empty area ends text editing. Tiles and the search field
    // are above this and keep their own clicks.
    MouseArea {
        anchors.fill: parent
        onClicked: searchField.deactivate()
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, Config.backgroundDim)
    }

    WallpaperStrip {
        id: strip
        anchors.fill: parent
        items: []
        onActivated: index => {
            // A click applies immediately and leaves the field, so later
            // typing does not silently change the query.
            searchField.deactivate();
            root.applyIndex(index);
        }
    }

    function applyInitialSelection() {
        if (root._initialSelectionDone || !model.ready || !awww.queryDone)
            return;

        // Start on the wallpaper awww is already showing. indexOfPath returns
        // -1 when that file is outside the current list, so index 0 stays.
        if (awww.currentPath !== "") {
            const i = strip.indexOfPath(awww.currentPath);
            if (i >= 0)
                strip.scrollTo(i, Config.scrollAnimationDuration);
        }
        root._initialSelectionDone = true;
    }

    /**
     * Replace the strip contents and pick the new selection.
     *
     * `targetPath` wins when it is still present. Otherwise the previous
     * selection is kept, unless `preferBest` asks for the best search match.
     * A positive `scrollDuration` animates the move; 0 jumps instantly.
     */
    function refreshStrip(targetPath, preferBest, scrollDuration) {
        const previous = strip.currentItemPath;
        // In scroll mode the list itself does not change; avoid resetting the
        // window (and interrupting a running scroll) on every keystroke.
        const nextItems = search.visibleItems;
        if (strip.items !== nextItems)
            strip.items = nextItems;

        let index = targetPath ? strip.indexOfPath(targetPath) : -1;
        if (index < 0) {
            if (preferBest && search.bestIndex >= 0)
                index = search.bestIndex;
            else if (!preferBest)
                index = strip.indexOfPath(previous);
            if (index < 0 && search.bestIndex >= 0)
                index = search.bestIndex;
            if (index < 0 && preferBest)
                index = strip.indexOfPath(previous);
        }
        if (index < 0)
            index = 0;

        if (scrollDuration > 0)
            strip.scrollTo(index, scrollDuration);
        else
            strip.jumpTo(index);
    }

    function handleQueryChanged() {
        if (search.query === "") {
            // Back to the full list and the pre-search wallpaper.
            if (root._searching) {
                root._searching = false;
                root.refreshStrip(root._preSearchPath, false,
                    search.effectiveMode === "scroll"
                        ? Config.searchAnimationDuration
                        : 0);
                root._preSearchPath = "";
            }
            return;
        }

        if (!root._searching) {
            root._searching = true;
            root._preSearchPath = strip.currentItemPath;
        }

        root.refreshStrip("", search.effectiveMode === "scroll",
            search.effectiveMode === "scroll"
                ? Config.searchAnimationDuration
                : 0);
    }

    function handleModeChanged() {
        if (search.query === "")
            root.refreshStrip("", false, 0);
        else
            root.refreshStrip("", search.effectiveMode === "scroll",
                search.effectiveMode === "scroll"
                    ? Config.searchAnimationDuration
                    : 0);
    }

    function cancelSearch() {
        if (searchField.text !== "")
            searchField.text = ""; // clears the query and restores the list
        else
            searchField.deactivate();
    }

    Connections {
        target: model
        function onLoaded() { root.applyInitialSelection() }
    }

    Connections {
        target: search
        function onItemsChanged() { root.refreshStrip("", false, 0) }
        function onQueryChanged() { root.handleQueryChanged() }
        function onModeChanged() { root.handleModeChanged() }
    }

    Connections {
        target: awww
        function onQueried() { root.applyInitialSelection() }
        function onApplied(path) {
            if (Config.closeOnApply)
                Qt.quit();
        }
    }

    Connections {
        target: strip
        function onNavigated() { root._initialSelectionDone = true }
    }

    function applyIndex(index) {
        // Filtering changes the strip's list, so read from it rather than
        // from the model.
        const item = strip.items[index];
        if (!item)
            return;

        root._initialSelectionDone = true;

        // Re-applying the current wallpaper has no visible effect.
        if (item.path === awww.currentPath) {
            if (Config.closeOnApply)
                Qt.quit();
            return;
        }

        awww.apply(item.path);
    }

    // Status shown at the bottom of the overlay. Errors take priority over
    // progress and empty-state hints.
    readonly property string statusText: {
        const errors = [];
        if (model.error !== "")
            errors.push("Scan: " + model.error);
        if (awww.error !== "")
            errors.push("awww: " + awww.error);
        if (errors.length > 0)
            return errors.join("\n");
        if (!Config.showInfoNotifications)
            return "";
        if (awww.applying)
            return "Applying wallpaper...";
        if (model.scanning)
            return "Scanning wallpapers...";
        const q = search.query.trim();
        if (q !== "") {
            if (search.matchCount === 0)
                return "No matches for \"" + q + "\"";
            return search.matchCount + (search.matchCount === 1 ? " match" : " matches");
        }
        if (model.ready && model.items.length === 0)
            return "No wallpapers found in " + Config.wallpaperDir;
        return "";
    }

    readonly property bool statusIsError: model.error !== "" || awww.error !== ""

    Rectangle {
        id: statusBox
        z: 2000
        visible: root.statusText !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        // Reserve the bottom band while the search field is anchored there,
        // so the two never overlap.
        anchors.bottomMargin: Config.search.verticalAlignment === "bottom"
            ? Math.max(32, Math.max(0, Config.search.margin) + searchField.height + 12)
            : 32
        width: Math.min(parent.width - 64, Math.max(180, statusMetrics.width + 32))
        height: statusText.contentHeight + 24
        radius: 8
        color: root.statusIsError
            ? Qt.rgba(0.30, 0.04, 0.04, 0.94)
            : Qt.rgba(0, 0, 0, 0.78)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)

        TextMetrics {
            id: statusMetrics
            text: root.statusText
            font.pixelSize: 16
        }

        Text {
            id: statusText
            anchors.centerIn: parent
            width: statusBox.width - 32
            text: root.statusText
            color: "white"
            font.pixelSize: 16
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // ApplicationShortcut fires regardless of which child has focus. The
    // navigation shortcuts stay disabled while the search field is edited:
    // SearchField forwards plain arrows and Enter to the same actions, and
    // keeps Ctrl/Shift combinations for text editing.
    Shortcut {
        sequence: "Left"
        context: Qt.ApplicationShortcut
        enabled: !searchField.editing
        onActivated: strip.prev()
    }
    Shortcut {
        sequence: "Right"
        context: Qt.ApplicationShortcut
        enabled: !searchField.editing
        onActivated: strip.next()
    }

    Shortcut {
        sequence: "Ctrl+F"
        context: Qt.ApplicationShortcut
        onActivated: searchField.activate()
    }

    // Enter stays disabled until the first scan completes.
    Shortcut {
        sequence: "Return"
        context: Qt.ApplicationShortcut
        enabled: model.ready && !searchField.editing
        onActivated: root.applyIndex(strip.currentIndex)
    }

    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        enabled: !searchField.editing
        onActivated: Qt.quit()
    }

    /**
     * Toggle target for scripts/open-picker.sh:
     *
     *     qs ipc -p <project dir> call wallpaperPicker close
     *
     * The typed return value is required for registration.
     */
    IpcHandler {
        target: "wallpaperPicker"

        function close(): void { Qt.quit(); }
    }
}
