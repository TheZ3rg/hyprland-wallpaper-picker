pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * Focused-monitor dimensions and design-pixel scaling.
 *
 * Config sizes are already ratios of the monitor and must not be passed
 * through px(). Use px() only for fixed chrome constants authored against a
 * 1440px-tall reference.
 */
Singleton {
    id: root

    readonly property var screen: {
        const monitor = Hyprland.focusedMonitor;
        if (!monitor)
            return null;
        return Quickshell.screens.find(s => s.name === monitor.name) ?? null;
    }

    readonly property int width: root.screen ? root.screen.width : 0
    readonly property int height: root.screen ? root.screen.height : 0

    readonly property real referenceHeight: 1440
    readonly property real scale: root.height > 0
        ? root.height / root.referenceHeight
        : 1

    function px(value) {
        return Math.max(0, Math.round(value * root.scale));
    }

    function hairline() {
        return Math.max(1, Math.round(root.scale));
    }
}
