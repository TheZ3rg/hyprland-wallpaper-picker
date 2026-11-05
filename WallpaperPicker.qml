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

    // Above tiled and floating windows, below lock screens and notification
    // daemons.
    WlrLayershell.layer: WlrLayer.Top

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

    AwwwBackend {
        id: awww
    }

    WallpaperModel {
        id: model
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, Config.backgroundDim)
    }

    WallpaperStrip {
        id: strip
        anchors.fill: parent
        items: model.items
        onActivated: index => root.applyIndex(index)
    }

    Connections {
        target: model
        function onLoaded() {
            // Start on the wallpaper awww is already showing. findIndex
            // returns -1 when that file is outside the folder, so index 0
            // remains the fallback.
            const i = model.items.findIndex(it => it.path === awww.currentPath);
            if (i >= 0)
                strip.currentIndex = i;
        }
    }

    function applyIndex(index) {
        const item = model.items[index];
        if (!item)
            return;

        // Re-applying the current wallpaper has no visible effect.
        if (item.path === awww.currentPath)
            return;

        awww.apply(item.path);

        if (Config.closeOnApply)
            Qt.quit();
    }

    // ApplicationShortcut fires regardless of which child has focus.
    Shortcut {
        sequence: "Left"
        context: Qt.ApplicationShortcut
        onActivated: strip.prev()
    }
    Shortcut {
        sequence: "Right"
        context: Qt.ApplicationShortcut
        onActivated: strip.next()
    }

    // Enter stays disabled until the first scan completes.
    Shortcut {
        sequence: "Return"
        context: Qt.ApplicationShortcut
        enabled: model.ready
        onActivated: root.applyIndex(strip.currentIndex)
    }

    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
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
