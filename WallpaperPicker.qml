import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
   Root object of the picker.
 
   Every other item in this file is a child of this window, i.e. drawn inside
   it.
 */
PanelWindow {
    id: root

    visible: true

    /*
       Which monitor to open the picker on.

         Quickshell.screens            -> all outputs Quickshell knows about
                                         (objects with `.name`, e.g. "DP-2")
         Hyprland.focusedMonitor?.name -> name of Hyprland's focused monitor.
                                         `?.` yields undefined when there is
                                         no focused monitor yet (startup,
                                         hotplug), instead of erroring.
         find(...)                     -> matching screen, or undefined
         ?? Quickshell.screens[0]      -> nullish fallback to the first output

       Result: picker opens on the focused monitor. These are bindings,
       so if focus moves to another monitor while the picker is open, the
       window may follow it.
     */
    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)
        ?? Quickshell.screens[0]

    /*
       Whether the compositor reserves screen space for this surface.
       Ignore = do not shift/maximise other windows as if a bar appeared;
       this is an overlay, not a panel.
     */
    exclusionMode: ExclusionMode.Ignore

    /*
       Background colour of the window surface itself. Transparent so the
       live desktop shows through.
     */
    color: "transparent"

    /*
       Which layer-shell layer to sit in. Order is Background < Bottom < Top <
       Overlay. Top is above normal tiled/floating windows but below Overlay
       (lock screens, notification daemons, ...).
     */
    WlrLayershell.layer: WlrLayer.Top

    /*
       A name Hyprland can match in `layerrule` (e.g. to enable blur and
       ignore alpha for this window). Must match your hyprland.conf.
     */
    WlrLayershell.namespace: "quickshell:wallpaperPicker"

    /*
       Keyboard focus policy:
         None      - never receives keyboard input
         OnDemand  - only when clicked
         Exclusive - takes keyboard focus while mapped, so keys go here
                     instead of the focused app. Required for the Shortcuts
                     below to work reliably.
     */
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    /*
       Layer-shell windows are placed by anchors, not x/y.
       All four sides = cover the entire output
     */
    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    // Invisible logic-only component that wraps the `awww` CLI
    AwwwBackend {
        id: awww
    }

    // Invisible logic-only component
    WallpaperModel {
        id: model
    }

    /*
       Fullscreen dim layer over the (compositor-blurred) desktop.
       Qt.rgba() returns a colour with alpha; backgroundDim is 0..1.
     */
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, Config.backgroundDim)
    }

    /*
       The actual coverflow strip. `items:` is a binding to the model's array,
       so the strip repopulates automatically once the scan finishes.
     */
    WallpaperStrip {
        id: strip
        anchors.fill: parent
        items: model.items
        onActivated: index => root.applyIndex(index)
    }

    /* TODO: Check this docs
       Declarative signal connection: while `target` is `model`, any signal it
       emits calls `on<SignalName>` here. `loaded()` is defined inside
       WallpaperModel and fires after the first scan. In Qt 6, handlers are
       written as functions (`function onLoaded() {}`).
     */
    Connections {
        target: model
        function onLoaded() {
            /*
               Start with the currently displayed wallpaper selected.
               findIndex returns -1 when the current file is not in the folder
               (e.g. it was deleted), in which case we keep index 0.
             */
            const i = model.items.findIndex(it => it.path === awww.currentPath);
            if (i >= 0)
                strip.currentIndex = i;
        }
    }

    // Apply the wallpaper at `index` in the model and close the picker.
    function applyIndex(index) {
        const item = model.items[index];
        // Out of range (e.g. empty folder, or a stale index). Nothing to do.
        if (!item)
            return;

        // Picking the wallpaper that is already set does nothing.
        if (item.path === awww.currentPath)
            return;

        awww.apply(item.path);

        if (Config.closeOnApply)
            Qt.quit();
    }

    /* TODO: Check this docs
       ---- Keyboard ----
       Shortcut handles one key (sequence) for the whole Qt application.
       `context: Qt.ApplicationShortcut` means it fires regardless of which
       child item currently has focus, as long as this window is focused.
       (For complex/multi-key input you would use Keys.onPressed instead.)
     */

    // Previous / next wallpaper.
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

    /*
       Apply. Disabled until the first scan has completed, so Enter cannot
       act on an empty list.
     */
    Shortcut {
        sequence: "Return"
        context: Qt.ApplicationShortcut
        enabled: model.ready
        onActivated: root.applyIndex(strip.currentIndex)
    }

    // Close without applying.
    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        onActivated: Qt.quit()
    }

    /** TODO: Check this docs
     * Exposes functions to `qs ipc`. With `target: "wallpaperPicker"`, other
     * processes can run:
     *
     *     qs ipc -p <this dir> call wallpaperPicker close
     *
     * which is what open-picker.sh uses as a toggle: if the picker is
     * already running this closes it, otherwise the script launches a new
     * one. Functions must be typed (here `: void`) to be exposed.
     */
    IpcHandler {
        target: "wallpaperPicker"

        function close(): void { Qt.quit(); }
    }
}
