import QtQuick

/**
 * Search input shown over the wallpaper strip.
 *
 * The field is always visible and dims while it is not being edited; click it
 * or press Ctrl+F to start typing. The picker decides what a commit or a
 * cancellation does, so this component only reports those events.
 */
Rectangle {
    id: root

    // Current text. Assigning it replaces the query.
    property alias text: input.text

    // True while the field holds keyboard focus.
    readonly property bool editing: input.activeFocus

    signal committed()
    signal canceled()

    function activate() {
        input.forceActiveFocus();
        input.selectAll();
    }

    function deactivate() {
        input.focus = false;
    }

    readonly property string horizontal: {
        const v = Config.search.horizontalAlignment;
        return (v === "left" || v === "center" || v === "right") ? v : "center";
    }

    readonly property string vertical: {
        const v = Config.search.verticalAlignment;
        return (v === "top" || v === "center" || v === "bottom") ? v : "top";
    }

    readonly property int edgeMargin: Math.max(0, Config.search.margin)

    width: Math.max(140, Math.min(420, parent.width - 2 * root.edgeMargin))
    height: 44
    radius: 10
    color: Qt.rgba(0, 0, 0, root.editing ? 0.84 : 0.62)
    border.width: 1
    border.color: root.editing ? Qt.rgba(1, 1, 1, 0.38) : Qt.rgba(1, 1, 1, 0.12)
    opacity: root.editing ? 1 : Config.search.unfocusedOpacity

    // Position is computed instead of anchored: a conditional set of
    // anchors.left/right/horizontalCenter would conflict in Qt.
    readonly property real _x: {
        if (root.horizontal === "left")
            return root.edgeMargin;
        if (root.horizontal === "right")
            return parent.width - root.width - root.edgeMargin;
        return (parent.width - root.width) / 2;
    }

    readonly property real _y: {
        if (root.vertical === "top")
            return root.edgeMargin;
        if (root.vertical === "bottom")
            return parent.height - root.height - root.edgeMargin;
        return (parent.height - root.height) / 2;
    }

    x: root._x
    y: root._y

    Behavior on opacity {
        NumberAnimation {
            duration: 150
            easing.type: Easing.OutCubic
        }
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text === ""
        text: "Search wallpapers"
        color: "white"
        opacity: 0.45
        font.pixelSize: 16
    }

    TextInput {
        id: input

        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        verticalAlignment: TextInput.AlignVCenter
        color: "white"
        selectionColor: Qt.rgba(1, 1, 1, 0.25)
        selectedTextColor: "white"
        font.pixelSize: 16
        clip: true
        activeFocusOnPress: true

        onAccepted: root.committed()
        Keys.onEscapePressed: event => {
            root.canceled();
            event.accepted = true;
        }

        // Do not steal focus when the overlay opens; Ctrl+F or a click
        // activates the field.
        Component.onCompleted: input.focus = false
    }

    // Discoverability hint; hidden on narrow fields where it would overlap
    // the placeholder.
    Text {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.editing && input.text === "" && root.width >= 280
        text: "Ctrl+F"
        color: "white"
        opacity: 0.30
        font.pixelSize: 12
    }
}
