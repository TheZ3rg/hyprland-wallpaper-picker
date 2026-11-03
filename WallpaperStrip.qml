import QtQuick

/**
 * Horizontal coverflow strip of wallpapers.
 *
 * Items are positioned manually (not by a ListView) so their spacing follows
 * their *scaled* width - this is what gives the tight, tapered look toward the
 * edges. The centred item is interpolated continuously, so moving the
 * selection slides the whole row smoothly.
 */
Item {
    id: root

    // Flat list from WallpaperModel: { path, source, thumb, aspect }.
    property var items: []

    // Index of the centred (selected) item. Assigning it animates `position`.
    property int currentIndex: 0

    // Emitted when a tile is clicked; WallpaperPicker applies it.
    signal activated(int index)

    // Number of wallpapers, unscaled tile height, and gap between tiles.
    readonly property int count: items.length
    readonly property real baseHeight: height * Config.itemHeightRatio
    readonly property real gap: Config.coverflow.spacingRatio * baseHeight

    // Animated scroll position, in index units (fractional while animating).
    property real position: 0
    Behavior on position {
        NumberAnimation {
            duration: Config.animationDuration
            easing.type: Easing.OutCubic
        }
    }

    // Jump the animation whenever the selection changes.
    onCurrentIndexChanged: position = currentIndex

    // Keep the selection in range when the model shrinks or empties.
    onCountChanged: {
        if (count === 0)
            currentIndex = 0;
        else if (currentIndex > count - 1)
            currentIndex = count - 1;
    }

    // Move one item left/right, clamped to the ends.
    function next() { if (currentIndex < count - 1) currentIndex++; }
    function prev() { if (currentIndex > 0) currentIndex--; }

    // Scale falloff by distance from the centre: centerScale at the centre,
    // edgeScale `falloffRange` items away.
    function scaleForIndex(i) {
        if (!Config.coverflow.enabled)
            return 1;
        const d = Math.abs(i - position);
        const t = Math.min(1, d / Math.max(0.001, Config.coverflow.falloffRange));
        return Config.coverflow.centerScale
            + (Config.coverflow.edgeScale - Config.coverflow.centerScale) * t;
    }

    // Cumulative layout, recomputed whenever position, count or size changes.
    // Each entry is { x, w, h, s }: left edge before centring, width, height
    // and scale. Width follows the image aspect so tiles keep their shape.
    readonly property var metrics: {
        const out = [];
        let x = 0;
        for (let i = 0; i < count; ++i) {
            const s = scaleForIndex(i);
            const h = baseHeight * s;
            // 0.7 is a portrait fallback for items without a known aspect.
            const a = (items[i] && items[i].aspect) ? items[i].aspect : 0.7;
            const w = h * a;
            out.push({ x: x, w: w, h: h, s: s });
            x += w + gap;
        }
        return out;
    }

    // Centre of the item at fractional position `p`, linearly interpolated
    // between neighbours. This is what keeps the row moving continuously
    // while `position` animates.
    function centreFor(p) {
        const n = metrics.length;
        if (n === 0)
            return 0;
        const k = Math.max(0, Math.min(n - 1, Math.floor(p)));
        const f = p - k;
        const a = metrics[k].x + metrics[k].w / 2;
        if (k + 1 >= n)
            return a;
        const b = metrics[k + 1].x + metrics[k + 1].w / 2;
        return a + (b - a) * f;
    }

    // Offset that puts the interpolated centre at the middle of the strip.
    readonly property real rowTranslate: width / 2 - centreFor(position)

    // One delegate per wallpaper. All geometry comes from `metrics`, so the
    // Repeater itself does not need to know the layout order.
    Repeater {
        model: root.items

        delegate: Item {
            id: cell
            // Injected by the Repeater: model index and our item object.
            required property int index
            required property var modelData

            // `m` is null before the first layout pass; dist/shown guard it.
            readonly property var m: root.metrics[index] ?? null
            readonly property real dist: Math.abs(index - root.position)
            readonly property bool shown: m !== null && dist <= Config.visibleRange
            readonly property real scaleFactor: m ? m.s : 1

            // Fade each thumbnail in as it finishes decoding, so the strip
            // doesn't pop in item by item. 0 disables the fade.
            property bool decoded: false
            opacity: (Config.thumbnailFadeInDuration > 0 && !cell.decoded) ? 0 : 1
            Behavior on opacity {
                NumberAnimation {
                    duration: Math.max(1, Config.thumbnailFadeInDuration)
                    easing.type: Easing.OutCubic
                }
            }

            // Off-screen tiles are hidden and unload their images, which keeps
            // scrolling cheap and memory bounded.
            visible: shown
            width: m ? m.w : 0
            height: m ? m.h : 0
            x: (m ? m.x : 0) + root.rowTranslate
            y: root.height / 2 - height / 2
            // Lower distance = higher z, so the centre tile overlaps the edges.
            z: 1000 - dist

            Image {
                id: img
                anchors.fill: parent
                // Empty source outside the visible window releases the image.
                source: cell.shown ? cell.modelData.thumb : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true // decode off the UI thread
                cache: true
                smooth: true
                onStatusChanged: {
                    // Show the tile (and fade it in) once decoding settles,
                    // even if it failed, so a broken thumbnail can't vanish.
                    if (status === Image.Ready || status === Image.Error)
                        cell.decoded = true;
                }
            }

            // Thin outline so dark wallpapers still read as separate tiles.
            Rectangle {
                anchors.fill: parent
                radius: Config.thumbnails.cornerRadius > 0
                    ? Config.thumbnails.cornerRadius * (cell.width / Math.max(1, Config.thumbnails.width))
                    : 0
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.10)
            }

            // Click a tile to apply it.
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.activated(cell.index)
            }
        }
    }

    // Mouse wheel / trackpad: one item per notch. High-resolution deltas are
    // accumulated so a single trackpad swipe does not jump many items at once.
    WheelHandler {
        id: wheel
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        property real acc: 0

        onWheel: event => {
            wheel.acc += event.angleDelta.y;
            const notch = 120; // one classic wheel notch
            while (Math.abs(wheel.acc) >= notch) {
                if (wheel.acc > 0)
                    root.prev();
                else
                    root.next();
                wheel.acc -= wheel.acc > 0 ? notch : -notch;
            }
            event.accepted = true;
        }
        onCanceled: wheel.acc = 0
    }
}
