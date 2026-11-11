import QtQuick

/**
 * Derives the wallpapers matching a search query.
 *
 * Matching is case-insensitive and only looks at the file's base name without
 * its extension. Results are ranked: exact names first, then names starting
 * with the query, then names containing it; original order is kept inside each
 * group.
 *
 * `visibleItems` is what the strip should display. In "filter" mode it holds
 * only the matches in ranked order; otherwise it is the complete list.
 */
Item {
    id: root

    // Logic-only item: it draws nothing.
    visible: false
    width: 0
    height: 0

    // Flat list from WallpaperModel:
    // { path, thumb, aspect, preview, live, video, animated }.
    property var items: []

    property string query: ""

    // "scroll" | "filter"; unknown values fall back to "scroll".
    property string mode: "scroll"

    readonly property string effectiveMode: root.mode === "filter" ? "filter" : "scroll"

    readonly property string _needle: root.query.trim().toLowerCase()

    // Indices into `items`, ranked. Empty while the query is empty.
    readonly property var matches: {
        const found = [];
        if (root._needle === "")
            return found;

        const exact = [];
        const prefix = [];
        const substring = [];

        for (let i = 0; i < root.items.length; ++i) {
            const item = root.items[i];
            if (!item)
                continue;

            const name = root.nameOf(item.path);
            const pos = name.indexOf(root._needle);
            if (pos < 0)
                continue;

            if (pos === 0) {
                if (name.length === root._needle.length)
                    exact.push(i);
                else
                    prefix.push(i);
            } else {
                substring.push(i);
            }
        }

        return exact.concat(prefix, substring);
    }

    readonly property int matchCount: root.matches.length

    readonly property var visibleItems: {
        if (root.effectiveMode !== "filter" || root._needle === "")
            return root.items;

        const out = [];
        for (let i = 0; i < root.matches.length; ++i)
            out.push(root.items[root.matches[i]]);
        return out;
    }

    // Index into `visibleItems` of the best match, or -1 without matches.
    readonly property int bestIndex: {
        if (root._needle === "" || root.matches.length === 0)
            return -1;
        return root.effectiveMode === "filter" ? 0 : root.matches[0];
    }

    // Base name without the final extension, lower-cased for matching.
    function nameOf(path) {
        const base = path.slice(path.lastIndexOf("/") + 1);
        const dot = base.lastIndexOf(".");
        const name = dot > 0 ? base.slice(0, dot) : base;
        return name.toLowerCase();
    }
}
