import QtQuick

/**
 * Horizontal coverflow strip of wallpapers.
 *
 * Tiles are positioned manually rather than by a ListView: spacing follows
 * each tile's scaled width, which produces the tapered look toward the edges.
 * The centre position is fractional and animated, so the whole row slides
 * smoothly between selections.
 *
 * Only a fixed window of delegates is instantiated. Slots keep their wallpaper
 * while it stays inside the window, so sliding the window during a long scroll
 * only reassigns the tiles entering and leaving it. The layout is
 * translation-invariant, so positioning the window locally gives the same
 * geometry as laying out the entire collection.
 */
Item {
    id: root

    // Flat list from WallpaperModel: { path, thumb, aspect }.
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
            // Long scrolls get their own duration; ordinary selection moves
            // keep the shorter one.
            duration: root.scrolling
                ? Config.scrollAnimationDuration
                : Config.selectionAnimationDuration
            easing.type: Easing.OutCubic
        }
    }

    // The window must cover every tile that can be shown while `position`
    // catches up with `currentIndex`, including the image-loading radius.
    readonly property int visibleRadius: Math.max(1, Config.visibleRange)
    readonly property int jumpLimit: Math.max(1, Math.floor(visibleRadius / 2))
    readonly property int windowRadius: visibleRadius + jumpLimit
    readonly property int windowSize: windowRadius * 2 + 1

    // Index of the first item in the window.
    property int windowStart: 0

    // True while a long scroll animates; the window follows `position`.
    property bool scrolling: false

    // Fixed delegate slots. slotIndex[s] is the global item index rendered by
    // slot s; keeping it stable means a window shift only changes the slots
    // that enter or leave the window.
    readonly property int slotCount: Math.min(count, windowSize)
    property var slotIndex: []

    // URLs whose images have finished decoding. A tile that reuses a slot or
    // re-enters the window starts opaque instead of fading in again.
    property var decodedUrls: ({})

    function jumpTo(index) {
        cancelScroll();
        animatePosition = false;
        currentIndex = Math.max(0, Math.min(count - 1, index));
        position = currentIndex;
        animatePosition = true;
        updateWindow(true);
    }

    /**
     * Animate to `index`.
     *
     * Nearby targets use the normal selection animation and fit inside the
     * current window. Distant targets mark the strip as scrolling: the window
     * then follows `position` frame by frame, so every intermediate tile is
     * rendered without instantiating the whole collection.
     */
    function scrollTo(index) {
        if (count === 0)
            return;

        const target = Math.max(0, Math.min(count - 1, index));
        if (target === currentIndex) {
            if (scrolling)
                finishTimer.restart();
            return;
        }

        const distance = Math.abs(target - currentIndex);
        if (distance <= jumpLimit) {
            currentIndex = target;
            return;
        }

        if (Config.scrollAnimationDuration <= 0) {
            jumpTo(target);
            return;
        }

        scrolling = true;
        finishTimer.restart();
        currentIndex = target;
    }

    function cancelScroll() {
        if (finishTimer)
            finishTimer.stop();
        scrolling = false;
    }

    function finishScroll() {
        if (!scrolling)
            return;

        scrolling = false;
        animatePosition = false;
        position = currentIndex;
        animatePosition = true;
        updateWindow(true);
    }

    // Path of the selected wallpaper, or "" when the list is empty.
    readonly property string currentItemPath: {
        const item = items[currentIndex];
        return item ? item.path : "";
    }

    // Index of the wallpaper with `path`, or -1. Used to keep the selection
    // across filtering and rescans.
    function indexOfPath(path) {
        if (!path)
            return -1;
        for (let i = 0; i < items.length; ++i) {
            if (items[i] && items[i].path === path)
                return i;
        }
        return -1;
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
        if (root.scrolling)
            return;

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

    // Keep the scrolling window centred on the animated position.
    function followScroll() {
        if (count <= windowSize)
            return;

        const maxStart = count - windowSize;
        const half = Math.floor(windowSize / 2);
        const start = Math.max(0, Math.min(maxStart,
            Math.round(position) - half));
        if (start !== windowStart)
            windowStart = start;
    }

    /**
     * Rebuild the slot mapping for the current window.
     *
     * Assignments still inside [windowStart, windowStart + slotCount) are
     * kept; only the freed slots are filled with newly visible indices.
     */
    function refreshSlots() {
        const n = slotCount;
        if (n <= 0) {
            slotIndex = [];
            return;
        }

        const start = windowStart;
        const end = start + n;
        const next = [];
        const used = ({});

        for (let s = 0; s < n; ++s) {
            const g = slotIndex[s];
            if (g >= start && g < end && used[g] !== true) {
                next[s] = g;
                used[g] = true;
            } else {
                next[s] = -1;
            }
        }

        let g = start;
        for (let s = 0; s < n; ++s) {
            if (next[s] !== -1)
                continue;
            while (g < end && used[g] === true)
                ++g;
            if (g >= end)
                break;
            next[s] = g;
            used[g] = true;
            ++g;
        }

        slotIndex = next;
    }

    onPositionChanged: {
        if (root.scrolling)
            root.followScroll();
    }

    onCurrentIndexChanged: {
        if (root.scrolling) {
            position = currentIndex;
            finishTimer.restart();
            return;
        }

        // A jump larger than the window margin cannot be animated through
        // tiles that are not instantiated.
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
        if (count === 0) {
            cancelScroll();
            currentIndex = 0;
        } else if (currentIndex > count - 1) {
            currentIndex = count - 1;
        }
        updateWindow(false);
    }

    onSlotCountChanged: refreshSlots()
    onWindowStartChanged: refreshSlots()

    // Replacing the list (initial load, filtered results) must recentre the
    // window; the old windowStart may point past the new end.
    onItemsChanged: {
        cancelScroll();
        updateWindow(true);
        refreshSlots();
    }
    onWindowSizeChanged: updateWindow(true)
    Component.onCompleted: {
        updateWindow(true);
        refreshSlots();
    }

    Timer {
        id: finishTimer

        // A little longer than the animation so the final frame is painted.
        interval: Math.max(1, Config.scrollAnimationDuration) + 50
        onTriggered: root.finishScroll()
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
        for (let slot = 0; slot < slotCount; ++slot) {
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
        model: root.slotCount

        delegate: Item {
            id: cell

            required property int index

            readonly property int dataIndex: {
                const g = root.slotIndex[index];
                return g === undefined ? -1 : g;
            }
            readonly property var entry:
                (cell.dataIndex >= 0 && cell.dataIndex < root.count)
                    ? root.items[cell.dataIndex]
                    : null

            // `m` is null until the slot is assigned or the layout is ready.
            readonly property var m: {
                if (cell.dataIndex < root.windowStart)
                    return null;
                return root.metrics[cell.dataIndex - root.windowStart] ?? null;
            }
            readonly property real dist: cell.dataIndex >= 0
                ? Math.abs(cell.dataIndex - root.position)
                : 1e9
            readonly property bool shown: cell.m !== null
                && cell.dist <= Config.visibleRange
            readonly property string thumbUrl: cell.entry ? cell.entry.thumb : ""

            // Preload tiles just outside the viewport while scrolling, so
            // they have a chance to decode before becoming visible.
            readonly property int loadRadius: Config.visibleRange
                + (root.scrolling ? root.jumpLimit : 0)
            readonly property bool loadable: cell.m !== null
                && cell.dist <= cell.loadRadius

            // Fade each tile in once its thumbnail has decoded, avoiding a
            // row that pops in item by item. The map makes a tile opaque when
            // it reuses a slot after the window shifted.
            property string decodedUrl: ""
            readonly property bool decoded: cell.thumbUrl !== ""
                && (cell.decodedUrl === cell.thumbUrl
                    || root.decodedUrls[cell.thumbUrl] === true)
            opacity: (Config.thumbnailFadeInDuration > 0 && !cell.decoded) ? 0 : 1
            Behavior on opacity {
                NumberAnimation {
                    duration: Math.max(1, Config.thumbnailFadeInDuration)
                    easing.type: Easing.OutCubic
                }
            }

            visible: shown
            width: m ? m.w : 0
            height: m ? m.h : 0
            x: (m ? m.x : 0) + root.rowTranslate
            y: root.height / 2 - height / 2
            // Higher tiles sit in front of lower ones.
            z: 1000 - Math.min(cell.dist, 1000)

            Image {
                anchors.fill: parent
                source: cell.loadable ? cell.thumbUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                onStatusChanged: {
                    // Reveal failed thumbnails too; otherwise a broken file
                    // would stay invisible instead of showing as an error.
                    if (status === Image.Ready || status === Image.Error) {
                        cell.decodedUrl = cell.thumbUrl;
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
                onClicked: {
                    if (cell.dataIndex >= 0)
                        root.activated(cell.dataIndex);
                }
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
