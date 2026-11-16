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
 *
 * In endless mode the window wraps around the list and may repeat wallpapers
 * when the folder is smaller than the window. In off mode the row is finite
 * and stops at the ends.
 */
Item {
    id: root

    // Flat list from WallpaperModel:
    // { path, thumb, aspect, preview, live, video, animated }.
    property var items: []

    // Assigning this animates `position` to the new index.
    property int currentIndex: 0

    // Unwrapped target index. In endless mode it may leave 0..count-1;
    // currentIndex remains the model index used by the rest of the picker.
    property int _virtualIndex: 0

    // True while jumpTo() updates the selection without animating. The
    // currentIndex handler must not turn that into a scroll.
    property bool _instantMove: false

    signal activated(int index)
    signal navigated()

    readonly property int count: items.length
    readonly property string loopMode: {
        const m = Config.strip.loopMode;
        return m === "endless" ? "endless" : "off";
    }
    readonly property bool endless: root.loopMode === "endless"
    readonly property real baseHeight: height * Config.thumbnails.heightRatio
    readonly property real baseWidth: height * Config.thumbnails.widthRatio
    readonly property real gap:
        Math.max(0, Math.round(height * Config.strip.spacingRatio))

    // Position of the current target in index units.
    readonly property real targetPosition: root.endless
        ? root._virtualIndex
        : root.currentIndex

    // True while the row is still moving toward targetPosition.
    readonly property bool moving: Math.abs(position - targetPosition) > 0.001

    // Scroll position in index units; fractional while animating.
    property real position: 0
    property bool animatePosition: true
    property int positionDuration: Math.max(0, Config.strip.selectionDuration)
    // Duration requested for the next target change, or -1 for the
    // distance-based default.
    property int _nextDuration: -1
    Behavior on position {
        enabled: root.animatePosition
        NumberAnimation {
            duration: root.positionDuration
            easing.type: Easing.OutCubic
        }
    }

    // The window must cover every tile that can be shown around the center,
    // including a small preload margin. WallpaperStrip is anchored to the
    // full-screen picker, so `width` is the focused monitor's logical width.
    readonly property int preloadTiles: 2
    readonly property bool hasGeometry: width > 0 && baseHeight > 0

    readonly property real minTileWidth:
        Math.max(1, baseWidth * Math.max(0.05, Config.strip.coverflow.edgeScale))

    readonly property int visibleRadius: hasGeometry
        ? Math.max(preloadTiles,
            Math.ceil((width / 2) / minTileWidth) + preloadTiles)
        : preloadTiles + 1

    readonly property int windowSize: visibleRadius * 2 + 1

    // Index of the first item in the window.
    property int windowStart: 0

    // Fixed delegate slots. slotIndex[s] is the window index rendered by
    // slot s; keeping it stable means a window shift only changes the slots
    // that enter or leave the window.
    readonly property int slotCount:
        count === 0 ? 0
        : (root.endless ? windowSize : Math.min(count, windowSize))
    property var slotIndex: []

    // URLs whose images have finished decoding. A tile that reuses a slot or
    // re-enters the window starts opaque instead of fading in again.
    property var decodedUrls: ({})

    // Model index for a window index. Finite modes clamp; endless mode wraps
    // around the list.
    function itemIndexFor(virtualIndex) {
        if (count === 0)
            return -1;
        if (!root.endless)
            return Math.max(0, Math.min(count - 1, virtualIndex));
        return ((virtualIndex % count) + count) % count;
    }

    function itemAt(virtualIndex) {
        const i = root.itemIndexFor(virtualIndex);
        return i >= 0 ? root.items[i] : null;
    }

    // Nearest window index for `modelIndex`, used by jumps and searches.
    // In endless mode this picks the shorter way around the list.
    function virtualForModel(modelIndex, fromPosition) {
        const model = Math.max(0, Math.min(count - 1, modelIndex));
        if (!root.endless || count === 0)
            return model;

        const base = Math.round(fromPosition);
        const currentModel = root.itemIndexFor(base);
        let delta = model - currentModel;

        while (delta > count / 2)
            delta -= count;
        while (delta < -count / 2)
            delta += count;

        return base + delta;
    }

    // Instant selection move used by initial load and filtering.
    function jumpTo(index) {
        if (count === 0)
            return;

        root._instantMove = true;
        animatePosition = false;
        const model = Math.max(0, Math.min(count - 1, index));
        root._virtualIndex = root.virtualForModel(model, root.position);
        root.currentIndex = model;
        root.position = root._virtualIndex;
        animatePosition = true;
        root._instantMove = false;
        updateWindow(true);
    }

    function snapTo(target) {
        animatePosition = false;
        position = target;
        animatePosition = true;
    }

    /**
     * Move to `index`.
     *
     * `duration` overrides the selection duration; 0 jumps instantly.
     * `position` always animates and the window always follows it, so there
     * is no separate long-scroll mode.
     */
    function scrollTo(index, duration) {
        if (count === 0)
            return;

        const model = Math.max(0, Math.min(count - 1, index));
        const target = root.virtualForModel(model, root.position);
        if (target === root._virtualIndex) {
            if (root.currentIndex !== model) {
                root._nextDuration = duration === undefined ? -1 : duration;
                root.currentIndex = model;
                root._nextDuration = -1;
            }
            return;
        }

        const moveDuration = duration === undefined
            ? Math.max(0, Config.strip.selectionDuration)
            : duration;
        if (moveDuration <= 0) {
            jumpTo(model);
            return;
        }

        root._nextDuration = moveDuration;
        root._virtualIndex = target;
        root.currentIndex = model;
        root._nextDuration = -1;
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
        if (count === 0)
            return;

        if (root.endless) {
            if (count > 1) {
                root._virtualIndex++;
                root.currentIndex = root.itemIndexFor(root._virtualIndex);
                navigated();
            }
            return;
        }

        if (currentIndex < count - 1) {
            root._virtualIndex = currentIndex + 1;
            currentIndex++;
            navigated();
        }
    }

    function prev() {
        if (count === 0)
            return;

        if (root.endless) {
            if (count > 1) {
                root._virtualIndex--;
                root.currentIndex = root.itemIndexFor(root._virtualIndex);
                navigated();
            }
            return;
        }

        if (currentIndex > 0) {
            root._virtualIndex = currentIndex - 1;
            currentIndex--;
            navigated();
        }
    }

    function updateWindow(force) {
        if (count === 0) {
            windowStart = 0;
            return;
        }

        const margin = Math.min(visibleRadius, Math.floor(windowSize / 3));
        const target = root.endless ? root._virtualIndex : root.currentIndex;
        let start = windowStart;

        if (root.endless) {
            if (force
                    || target < start + margin
                    || target > start + windowSize - 1 - margin) {
                start = target - Math.floor(windowSize / 2);
            }
        } else {
            const maxStart = Math.max(0, count - windowSize);
            if (force
                    || start > maxStart
                    || target < start + margin
                    || target > start + windowSize - 1 - margin) {
                start = Math.max(0, Math.min(maxStart,
                    target - Math.floor(windowSize / 2)));
            }
        }

        if (start !== windowStart)
            windowStart = start;
    }

    // Keep the window centered on the animated position.
    function followScroll() {
        if (count === 0)
            return;

        const half = Math.floor(windowSize / 2);
        let start;

        if (root.endless) {
            start = Math.round(position) - half;
        } else {
            if (count <= windowSize)
                return;
            const maxStart = count - windowSize;
            start = Math.max(0, Math.min(maxStart,
                Math.round(position) - half));
        }

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
            if (g !== null && g !== undefined
                    && g >= start && g < end && used[g] !== true) {
                next[s] = g;
                used[g] = true;
            } else {
                next[s] = null;
            }
        }

        let g = start;
        for (let s = 0; s < n; ++s) {
            if (next[s] !== null)
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

    onPositionChanged: root.followScroll()

    onCurrentIndexChanged: {
        const target = root.endless
            ? root._virtualIndex
            : root.currentIndex;

        if (root._instantMove) {
            root._nextDuration = -1;
            root.snapTo(target);
            updateWindow(true);
            return;
        }

        const duration = root._nextDuration >= 0
            ? root._nextDuration
            : Math.max(0, Config.strip.selectionDuration);
        root._nextDuration = -1;

        if (duration <= 0) {
            root.snapTo(target);
            return;
        }

        root.positionDuration = duration;
        position = target;
    }

    // Keep the selection valid when the model shrinks or empties.
    onCountChanged: {
        if (count === 0) {
            root._instantMove = true;
            root._virtualIndex = 0;
            currentIndex = 0;
            root._instantMove = false;
        } else {
            const model = Math.min(currentIndex, count - 1);
            root._virtualIndex = root.endless
                ? root.virtualForModel(model, root.position)
                : model;
            if (currentIndex !== model) {
                root._instantMove = true;
                currentIndex = model;
                root._instantMove = false;
            }
        }
        updateWindow(false);
    }

    onSlotCountChanged: refreshSlots()
    onWindowStartChanged: refreshSlots()

    // Changing loop mode changes how indices map, so re-anchor and recentre.
    onLoopModeChanged: {
        if (count === 0)
            return;

        root._virtualIndex = root.endless
            ? root.virtualForModel(root.currentIndex, root.position)
            : root.currentIndex;
        root.animatePosition = false;
        root.position = root._virtualIndex;
        root.animatePosition = true;
        root.updateWindow(true);
        root.refreshSlots();
    }

    // Replacing the list (initial load, filtered results) must recentre the
    // window; the old windowStart may point past the new end.
    onItemsChanged: {
        updateWindow(true);
        refreshSlots();
    }
    onWindowSizeChanged: updateWindow(true)
    Component.onCompleted: {
        updateWindow(true);
        refreshSlots();
    }

    function scaleForIndex(i) {
        if (!Config.strip.coverflow.enabled)
            return 1;
        const d = Math.abs(i - position);
        const t = Math.min(1,
            d / Math.max(0.001, Config.strip.coverflow.falloffRange));
        return Config.strip.coverflow.centerScale
            + (Config.strip.coverflow.edgeScale
                - Config.strip.coverflow.centerScale) * t;
    }

    // Layout for the current window, recomputed on every frame of the
    // animation. Each entry is { x, w, h, s }: left edge before centering,
    // width, height and scale. Width follows the image aspect. Coordinates
    // are local to `windowStart`; the offsets cancel when the row is centered.
    readonly property var metrics: {
        const out = [];
        let x = 0;
        for (let slot = 0; slot < slotCount; ++slot) {
            const i = windowStart + slot;
            const s = scaleForIndex(i);

            // The center card's extra size is part of the layout, so the
            // neighbours slide outward instead of being covered. The card
            // grows from the base tile size to the configured preview size;
            // width and height are independent multipliers.
            const centerWeight = Math.max(0, 1 - Math.abs(i - position));
            const item = root.itemAt(i);
            const hasPreview = item && item.preview !== "";
            const targetWidth = hasPreview
                ? baseWidth * Config.previews.widthScale
                : baseWidth;
            const targetHeight = hasPreview
                ? baseHeight * Config.previews.heightScale
                : baseHeight;
            const widthFactor = Config.strip.coverflow.enabled
                ? 1 + (Config.strip.coverflow.centerWidthScale - 1)
                    * centerWeight
                : 1;
            const heightFactor = Config.strip.coverflow.enabled
                ? 1 + (Config.strip.coverflow.centerHeightScale - 1)
                    * centerWeight
                : 1;

            const w = (baseWidth + (targetWidth - baseWidth) * centerWeight)
                * s * widthFactor;
            const h = (baseHeight + (targetHeight - baseHeight) * centerWeight)
                * s * heightFactor;
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

            readonly property var slot:
                root.slotIndex[index] ?? null
            readonly property bool hasSlot: cell.slot !== null
            readonly property int virtualIndex: cell.hasSlot ? cell.slot : 0
            readonly property int dataIndex:
                cell.hasSlot ? root.itemIndexFor(cell.virtualIndex) : -1
            readonly property var entry:
                (cell.dataIndex >= 0 && cell.dataIndex < root.count)
                    ? root.items[cell.dataIndex]
                    : null

            // `m` is null until the slot is assigned or the layout is ready.
            readonly property var m: {
                if (!cell.hasSlot || cell.virtualIndex < root.windowStart)
                    return null;
                return root.metrics[cell.virtualIndex - root.windowStart] ?? null;
            }
            readonly property real dist: cell.hasSlot
                ? Math.abs(cell.virtualIndex - root.position)
                : 1e9
            readonly property bool onScreen: cell.m !== null
                && cell.x + cell.width >= -root.baseHeight
                && cell.x <= root.width + root.baseHeight
            readonly property string thumbUrl: cell.entry ? cell.entry.thumb : ""

            readonly property real centerWeight: cell.hasSlot
                ? Math.max(0, 1 - Math.abs(cell.virtualIndex - root.position))
                : 0
            readonly property string previewUrl:
                cell.entry ? (cell.entry.preview ?? "") : ""
            readonly property bool animatedPreview:
                cell.entry ? (cell.entry.animated === true) : false
            readonly property bool previewActive:
                cell.previewUrl !== "" && cell.centerWeight > 0.001

            // Animated clips play only when the row is settled. While moving,
            // the center card keeps showing the static first frame.
            readonly property bool livePreviewActive:
                cell.animatedPreview && cell.previewActive && !root.moving

            // Keep the first frame visible while a clip loads.
            readonly property bool staticPreviewActive:
                cell.previewActive && (!cell.animatedPreview
                    || !(cell.livePreviewActive && cell.livePreviewLoaded))

            // True once the preview image has decoded. The base thumbnail is
            // hidden then, so the two crops never overlap visually.
            property bool previewLoaded: false
            property bool livePreviewLoaded: false

            // The derived window already includes the preload margin, so every
            // slot that exists is kept loaded.
            readonly property bool loadable: cell.m !== null

            // Fade each tile in once its thumbnail has decoded, avoiding a
            // row that pops in item by item. The map makes a tile opaque when
            // it reuses a slot after the window shifted.
            property string decodedUrl: ""
            readonly property bool decoded: cell.thumbUrl !== ""
                && (cell.decodedUrl === cell.thumbUrl
                    || root.decodedUrls[cell.thumbUrl] === true)
            opacity: (Config.thumbnails.fadeInDuration > 0 && !cell.decoded) ? 0 : 1
            Behavior on opacity {
                NumberAnimation {
                    duration: Math.max(1, Config.thumbnails.fadeInDuration)
                    easing.type: Easing.OutCubic
                }
            }

            visible: onScreen
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
                opacity: (cell.previewActive && cell.previewLoaded) ? 0 : 1
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

            // Wider, higher-resolution crop shown once the center card's
            // preview is ready. For animated wallpapers this is the first
            // frame of the clip until the clip itself is loaded. It stays
            // opaque; the widening animation reveals more of it instead of
            // cross-fading over the thumbnail.
            Image {
                id: previewImage

                anchors.fill: parent
                source: cell.staticPreviewActive ? cell.previewUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                opacity: (cell.staticPreviewActive && cell.previewLoaded) ? 1 : 0

                onSourceChanged: cell.previewLoaded = false
                onStatusChanged: cell.previewLoaded = (status === Image.Ready)
            }

            // Muted looping clip for the selected video or GIF. It replaces
            // the static first frame once decoded and pauses as soon as the
            // card leaves the center.
            AnimatedImage {
                id: livePreviewImage

                anchors.fill: parent
                source: cell.livePreviewActive ? cell.previewUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                smooth: true
                paused: !cell.livePreviewActive
                opacity: (cell.livePreviewActive && cell.livePreviewLoaded) ? 1 : 0

                onSourceChanged: cell.livePreviewLoaded = false
                onStatusChanged: cell.livePreviewLoaded = (status === Image.Ready)
            }

            // A faint outline keeps dark wallpapers distinguishable.
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.10)
            }

            // Marks wallpapers that animate on the desktop: videos and GIFs.
            Rectangle {
                id: liveBadge

                visible: Config.strip.showLiveBadge && cell.entry
                    && cell.entry.live === true && cell.width >= 56
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 6
                width: liveBadgeLabel.implicitWidth + 10
                height: liveBadgeLabel.implicitHeight + 4
                radius: 4
                color: Qt.rgba(0, 0, 0, 0.65)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.15)

                Text {
                    id: liveBadgeLabel
                    anchors.centerIn: parent
                    text: "LIVE"
                    color: "white"
                    font.pixelSize: 10
                    font.bold: true
                }
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
