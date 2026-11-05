import QtQuick

/**
 * Horizontal coverflow strip of wallpapers.
 *
 * Tiles are positioned manually rather than by a ListView: spacing follows
 * each tile's scaled width, which produces the tapered look toward the edges.
 * The centre position is fractional and animated, so the whole row slides
 * smoothly between selections.
 *
 * Only a window of delegates around the selection is instantiated. The
 * layout is translation-invariant, so positioning that window locally gives
 * the same geometry as laying out the entire collection.
 */
Item {
    id: root

    // Flat list from WallpaperModel: { path, source, thumb, aspect }.
    property var items: []

    // Assigning this animates `position` to the new index.
    property int currentIndex: 0

    signal activated(int index)
    signal navigated()

    readonly property int count: items.length
    readonly property real baseHeight: height * Config.itemHeightRatio
    readonly property real gap: Config.coverflow.spacingRatio * baseHeight

    // Scroll position in index units; fractional while animating.
    property real position: 0
    property bool animatePosition: true
    Behavior on position {
        enabled: root.animatePosition
        NumberAnimation {
            duration: Config.animationDuration
            easing.type: Easing.OutCubic
        }
    }

    // The window must cover every tile that can be shown while `position`
    // catches up with `currentIndex`, including the image-loading radius.
    readonly property int visibleRadius: Math.max(1, Config.visibleRange)
    readonly property int jumpLimit: Math.max(1, Math.floor(visibleRadius / 2))
    readonly property int windowRadius: visibleRadius + jumpLimit
    readonly property int windowSize: windowRadius * 2 + 1

    // Index of the first delegate in the window.
    property int windowStart: 0

    // URLs whose images have finished decoding. A delegate created after the
    // window shifts starts opaque instead of fading in a second time.
    property var decodedUrls: ({})

    function jumpTo(index) {
        animatePosition = false;
        currentIndex = Math.max(0, Math.min(count - 1, index));
        position = currentIndex;
        animatePosition = true;
    }

    function next() {
        if (currentIndex < count - 1) {
            currentIndex++;
            navigated();
        }
    }

    function prev() {
        if (currentIndex > 0) {
            currentIndex--;
            navigated();
        }
    }

    function updateWindow(force) {
        if (count === 0) {
            windowStart = 0;
            return;
        }

        const maxStart = Math.max(0, count - windowSize);
        const margin = Math.min(visibleRadius, Math.floor(windowSize / 3));
        let start = windowStart;

        if (force
                || start > maxStart
                || currentIndex < start + margin
                || currentIndex > start + windowSize - 1 - margin) {
            start = Math.max(0, Math.min(maxStart,
                currentIndex - Math.floor(windowSize / 2)));
        }

        if (start !== windowStart)
            windowStart = start;
    }

    onCurrentIndexChanged: {
        // A jump larger than the window margin cannot be animated through
        // delegates that were never instantiated.
        if (Math.abs(position - currentIndex) > jumpLimit) {
            animatePosition = false;
            position = currentIndex;
            animatePosition = true;
        } else {
            position = currentIndex;
        }
        updateWindow(false);
    }

    // Keep the selection valid when the model shrinks or empties.
    onCountChanged: {
        if (count === 0)
            currentIndex = 0;
        else if (currentIndex > count - 1)
            currentIndex = count - 1;
        updateWindow(false);
    }

    onItemsChanged: updateWindow(false)
    onWindowSizeChanged: updateWindow(true)
    Component.onCompleted: updateWindow(true)

    // Delegate window: entries are { item, index } with global indices.
    readonly property var windowItems: {
        const out = [];
        const end = Math.min(count - 1, windowStart + windowSize - 1);
        for (let i = windowStart; i <= end; ++i)
            out.push({ item: items[i], index: i });
        return out;
    }

    function scaleForIndex(i) {
        if (!Config.coverflow.enabled)
            return 1;
        const d = Math.abs(i - position);
        const t = Math.min(1, d / Math.max(0.001, Config.coverflow.falloffRange));
        return Config.coverflow.centerScale
            + (Config.coverflow.edgeScale - Config.coverflow.centerScale) * t;
    }

    // Layout for the current window, recomputed on every frame of the
    // animation. Each entry is { x, w, h, s }: left edge before centring,
    // width, height and scale. Width follows the image aspect. Coordinates
    // are local to `windowStart`; the offsets cancel when the row is centred.
    readonly property var metrics: {
        const out = [];
        let x = 0;
        for (let slot = 0; slot < windowItems.length; ++slot) {
            const i = windowStart + slot;
            const s = scaleForIndex(i);
            const h = baseHeight * s;
            const a = (items[i] && items[i].aspect) ? items[i].aspect : 0.7;
            const w = h * a;
            out.push({ x: x, w: w, h: h, s: s });
            x += w + gap;
        }
        return out;
    }

    // Centre of the tile at fractional local index `p`, interpolated between
    // its neighbours so the row keeps moving while `position` animates.
    function centreFor(p) {
        const n = metrics.length;
        if (n === 0)
            return 0;
        const k = Math.max(0, Math.min(n - 1, Math.floor(p)));
        const f = Math.max(0, Math.min(1, p - k));
        const a = metrics[k].x + metrics[k].w / 2;
        if (k + 1 >= n)
            return a;
        const b = metrics[k + 1].x + metrics[k + 1].w / 2;
        return a + (b - a) * f;
    }

    readonly property real rowTranslate:
        width / 2 - centreFor(position - windowStart)

    Repeater {
        model: root.windowItems

        delegate: Item {
            id: cell

            required property int index
            required property var modelData

            readonly property int dataIndex: modelData.index
            readonly property var entry: modelData.item

            // `m` is null until the first layout pass.
            readonly property var m: root.metrics[index] ?? null
            readonly property real dist: Math.abs(cell.dataIndex - root.position)
            readonly property bool shown: m !== null && dist <= Config.visibleRange
            readonly property string thumbUrl: cell.entry ? cell.entry.thumb : ""

            // Fade each tile in once its thumbnail has decoded, avoiding a
            // row that pops in item by item.
            property bool decoded: root.decodedUrls[cell.thumbUrl] === true
            opacity: (Config.thumbnailFadeInDuration > 0 && !cell.decoded) ? 0 : 1
            Behavior on opacity {
                NumberAnimation {
                    duration: Math.max(1, Config.thumbnailFadeInDuration)
                    easing.type: Easing.OutCubic
                }
            }

            // Hidden tiles also clear their image source, which releases the
            // decoded texture and bounds memory use.
            visible: shown
            width: m ? m.w : 0
            height: m ? m.h : 0
            x: (m ? m.x : 0) + root.rowTranslate
            y: root.height / 2 - height / 2
            // Higher tiles sit in front of lower ones.
            z: 1000 - dist

            Image {
                anchors.fill: parent
                source: cell.shown ? cell.thumbUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                onStatusChanged: {
                    // Reveal failed thumbnails too; otherwise a broken file
                    // would stay invisible instead of showing as an error.
                    if (status === Image.Ready || status === Image.Error) {
                        cell.decoded = true;
                        if (cell.thumbUrl !== "")
                            root.decodedUrls[cell.thumbUrl] = true;
                    }
                }
            }

            // A faint outline keeps dark wallpapers distinguishable.
            Rectangle {
                anchors.fill: parent
                radius: Config.thumbnails.cornerRadius > 0
                    ? Config.thumbnails.cornerRadius * (cell.width / Math.max(1, Config.thumbnails.width))
                    : 0
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.10)
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.activated(cell.dataIndex)
            }
        }
    }

    // Accumulate high-resolution trackpad deltas so one swipe does not jump
    // several wallpapers at once.
    WheelHandler {
        id: wheel
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        property real acc: 0

        onWheel: event => {
            wheel.acc += event.angleDelta.y;
            const notch = 120;
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
