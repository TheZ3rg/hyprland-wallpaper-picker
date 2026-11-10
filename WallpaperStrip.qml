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
 * In looped mode the window wraps around the list and slots may repeat
 * wallpapers when the folder is smaller than the window, so the strip never
 * shows an end.
 */
Item {
    id: root

    // Flat list from WallpaperModel: { path, thumb, aspect, preview }.
    property var items: []

    // Assigning this animates `position` to the new index.
    property int currentIndex: 0

    // Unwrapped target index. In looped mode it may leave 0..count-1;
    // currentIndex remains the model index used by the rest of the picker.
    property int _virtualIndex: 0

    signal activated(int index)
    signal navigated()

    readonly property int count: items.length
    readonly property bool looped: Config.strip.looped
    readonly property real baseHeight: height * Config.strip.itemHeightRatio
    readonly property real gap: Config.strip.spacing

    // Scroll position in index units; fractional while animating.
    property real position: 0
    property bool animatePosition: true
    // Duration of the current long scroll; set by scrollTo().
    property int activeScrollDuration: 0
    Behavior on position {
        enabled: root.animatePosition
        NumberAnimation {
            // Long scrolls get their own duration; ordinary selection moves
            // keep the shorter one.
            duration: root.scrolling
                ? root.activeScrollDuration
                : Config.strip.selectionDuration
            easing.type: Easing.OutCubic
        }
    }

    // The window must cover every tile that can be shown while `position`
    // catches up with `currentIndex`, including the image-loading radius.
    readonly property int visibleRadius: Math.max(1, Config.strip.visibleRange)
    readonly property int jumpLimit: Math.max(1, Math.floor(visibleRadius / 2))
    readonly property int windowRadius: visibleRadius + jumpLimit
    readonly property int windowSize: windowRadius * 2 + 1

    // Index of the first item in the window.
    property int windowStart: 0

    // True while a long scroll animates; the window follows `position`.
    property bool scrolling: false

    // True during the final part of a long scroll, when the focused card is
    // allowed to start widening before the scroll fully stops.
    property bool scrollFinishing: false

    // Start the widen this early, but never earlier than the widening itself.
    readonly property int widenLead:
        Math.max(0, Math.min(Config.previews.expandOverlap,
                                Config.previews.expandDuration))

    // Fixed delegate slots. slotIndex[s] is the window index rendered by
    // slot s; keeping it stable means a window shift only changes the slots
    // that enter or leave the window. In looped mode the window is always
    // full even when there are fewer wallpapers than slots.
    readonly property int slotCount:
        count === 0 ? 0
        : (root.looped ? windowSize : Math.min(count, windowSize))
    property var slotIndex: []

    // URLs whose images have finished decoding. A tile that reuses a slot or
    // re-enters the window starts opaque instead of fading in again.
    property var decodedUrls: ({})

    // Wider preview of the selected wallpaper, supplied by the scan manifest.
    readonly property string currentItemPreview: {
        const item = items[currentIndex];
        return item ? (item.preview ?? "") : "";
    }

    // 0 = narrow strip crop, 1 = wider focused crop. Waits for long scrolls
    // to finish (or their overlap window) and for a cached preview.
    property real previewBlend: Config.previews.enabled
        && (!scrolling || scrollFinishing)
        && currentItemPreview !== ""
        ? 1
        : 0
    Behavior on previewBlend {
        NumberAnimation {
            duration: Math.max(0, Config.previews.expandDuration)
            easing.type: Easing.OutCubic
        }
    }

    readonly property real focusedAspect:
        Math.max(0.05, Config.previews.aspectRatio * Config.strip.focusWidthScale)

    // Model index for a window index. Non-looped strips clamp; looped strips
    // wrap around the list.
    function itemIndexFor(virtualIndex) {
        if (count === 0)
            return -1;
        if (!root.looped)
            return Math.max(0, Math.min(count - 1, virtualIndex));
        return ((virtualIndex % count) + count) % count;
    }

    function itemAt(virtualIndex) {
        const i = root.itemIndexFor(virtualIndex);
        return i >= 0 ? root.items[i] : null;
    }

    // Nearest window index for `modelIndex`, used by jumps and searches.
    // In looped mode this picks the shorter way around the list.
    function virtualForModel(modelIndex, fromPosition) {
        const model = Math.max(0, Math.min(count - 1, modelIndex));
        if (!root.looped || count === 0)
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

    function jumpTo(index) {
        cancelScroll();
        animatePosition = false;
        const model = Math.max(0, Math.min(count - 1, index));
        root._virtualIndex = root.virtualForModel(model, root.position);
        root.currentIndex = model;
        root.position = root._virtualIndex;
        animatePosition = true;
        updateWindow(true);
    }

    function restartScrollTimers() {
        finishTimer.restart();
        if (root.widenLead > 0)
            widenLeadTimer.restart();
        else
            widenLeadTimer.stop();
    }

    /**
     * Animate to `index` over `duration` milliseconds.
     *
     * `duration` defaults to strip.scrollDuration. Nearby targets use the
     * normal selection animation and fit inside the current window. Distant
     * targets mark the strip as scrolling: the window then follows `position`
     * frame by frame, so every intermediate tile is rendered without
     * instantiating the whole collection.
     */
    function scrollTo(index, duration) {
        if (count === 0)
            return;

        const model = Math.max(0, Math.min(count - 1, index));
        const target = root.virtualForModel(model, root.position);
        if (target === root._virtualIndex) {
            if (root.currentIndex !== model)
                root.currentIndex = model;
            if (scrolling)
                restartScrollTimers();
            return;
        }

        const distance = Math.abs(target - root._virtualIndex);
        if (distance <= jumpLimit) {
            root._virtualIndex = target;
            root.currentIndex = model;
            return;
        }

        const scrollDuration = duration === undefined
            ? Config.strip.scrollDuration
            : duration;
        if (scrollDuration <= 0) {
            jumpTo(model);
            return;
        }

        activeScrollDuration = scrollDuration;
        scrollFinishing = false;
        scrolling = true;
        restartScrollTimers();
        root._virtualIndex = target;
        root.currentIndex = model;
    }

    function cancelScroll() {
        if (finishTimer)
            finishTimer.stop();
        if (widenLeadTimer)
            widenLeadTimer.stop();
        scrollFinishing = false;
        scrolling = false;
    }

    function finishScroll() {
        if (!scrolling)
            return;

        widenLeadTimer.stop();
        scrollFinishing = false;
        scrolling = false;
        animatePosition = false;
        position = root._virtualIndex;
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
        if (count === 0)
            return;

        if (root.looped && count > 1) {
            root._virtualIndex++;
            root.currentIndex = root.itemIndexFor(root._virtualIndex);
            navigated();
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

        if (root.looped && count > 1) {
            root._virtualIndex--;
            root.currentIndex = root.itemIndexFor(root._virtualIndex);
            navigated();
            return;
        }

        if (currentIndex > 0) {
            root._virtualIndex = currentIndex - 1;
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

        const margin = Math.min(visibleRadius, Math.floor(windowSize / 3));
        const target = root._virtualIndex;
        let start = windowStart;

        if (root.looped) {
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

    // Keep the scrolling window centred on the animated position.
    function followScroll() {
        if (count === 0)
            return;

        const half = Math.floor(windowSize / 2);
        let start;

        if (root.looped) {
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

    onPositionChanged: {
        if (root.scrolling)
            root.followScroll();
    }

    onCurrentIndexChanged: {
        const target = root.looped ? root._virtualIndex : root.currentIndex;

        if (root.scrolling) {
            position = target;
            root.scrollFinishing = false;
            root.restartScrollTimers();
            return;
        }

        // A jump larger than the window margin cannot be animated through
        // tiles that are not instantiated.
        if (Math.abs(position - target) > jumpLimit) {
            animatePosition = false;
            position = target;
            animatePosition = true;
        } else {
            position = target;
        }
        updateWindow(false);
    }

    // Keep the selection valid when the model shrinks or empties.
    onCountChanged: {
        if (count === 0) {
            cancelScroll();
            root._virtualIndex = 0;
            currentIndex = 0;
        } else {
            const model = Math.min(currentIndex, count - 1);
            root._virtualIndex = root.looped
                ? root.virtualForModel(model, root.position)
                : model;
            if (currentIndex !== model)
                currentIndex = model;
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
        interval: Math.max(1, root.activeScrollDuration) + 50
        onTriggered: root.finishScroll()
    }

    Timer {
        id: widenLeadTimer

        // Fires early enough for the widen to overlap the end of the scroll.
        interval: Math.max(0, root.activeScrollDuration - root.widenLead)
        onTriggered: {
            if (root.scrolling)
                root.scrollFinishing = true;
        }
    }

    function scaleForIndex(i) {
        if (!Config.strip.coverflowEnabled)
            return 1;
        const d = Math.abs(i - position);
        const t = Math.min(1, d / Math.max(0.001, Config.strip.falloffRange));
        return Config.strip.centerScale
            + (Config.strip.edgeScale - Config.strip.centerScale) * t;
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

            // The focused tile's extra size is part of the layout, so the
            // neighbours slide outward instead of being covered. Width only
            // widens once the focused preview is ready.
            const focus = Math.max(0, 1 - Math.abs(i - position));
            const heightFactor =
                1 + (Config.strip.focusHeightScale - 1) * focus;

            const item = root.itemAt(i);
            const a = (item && item.aspect) ? item.aspect : 0.7;
            const hasPreview = item && item.preview !== "";
            const wideAspect = hasPreview ? root.focusedAspect : a;

            // During the overlap only the destination tile widens; otherwise
            // every passing tile with a cached preview would grow.
            const wideFocus = root.scrolling
                ? (i === root._virtualIndex ? focus : 0)
                : focus;
            const aspect = a + (wideAspect - a) * wideFocus * root.previewBlend;

            const h = baseHeight * s * heightFactor;
            const w = h * aspect;
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
            readonly property bool shown: cell.m !== null
                && cell.dist <= Config.strip.visibleRange
            readonly property string thumbUrl: cell.entry ? cell.entry.thumb : ""

            readonly property real focusWeight: cell.hasSlot
                ? Math.max(0, 1 - Math.abs(cell.virtualIndex - root.position))
                : 0
            readonly property string previewUrl:
                cell.entry ? (cell.entry.preview ?? "") : ""
            readonly property bool previewActive:
                cell.previewUrl !== "" && cell.focusWeight > 0.001

            // True once the preview image has decoded. The base thumbnail is
            // hidden then, so the two crops never overlap visually.
            property bool previewLoaded: false

            // Preload tiles just outside the viewport while scrolling, so
            // they have a chance to decode before becoming visible.
            readonly property int loadRadius: Config.strip.visibleRange
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
            opacity: (Config.thumbnails.fadeInDuration > 0 && !cell.decoded) ? 0 : 1
            Behavior on opacity {
                NumberAnimation {
                    duration: Math.max(1, Config.thumbnails.fadeInDuration)
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

            // Wider, higher-resolution crop shown once the focused tile's
            // preview is ready. It stays opaque; the widening animation
            // reveals more of it instead of cross-fading over the thumbnail.
            Image {
                id: previewImage

                anchors.fill: parent
                source: cell.previewActive ? cell.previewUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                opacity: (cell.previewActive && cell.previewLoaded) ? 1 : 0

                onSourceChanged: cell.previewLoaded = false
                onStatusChanged: cell.previewLoaded = (status === Image.Ready)
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
