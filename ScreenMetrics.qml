pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * The monitor the picker follows.
 *
 * Sizes in QML are logical pixels: Qt and the compositor apply the screen's
 * scale factor, so the picker does not scale itself. Fixed sizes are written
 * as plain numbers; sizes that should fill the screen are fractions of the
 * monitor height.
 */
Singleton {
    id: root

    readonly property var screen: {
        const monitor = Hyprland.focusedMonitor;
        if (!monitor)
            return null;
        return Quickshell.screens.find(s => s.name === monitor.name) ?? null;
    }
}
