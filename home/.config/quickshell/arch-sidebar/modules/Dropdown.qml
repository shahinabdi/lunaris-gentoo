import QtQuick

// Drop-down menu in the sidebar style: a button with the current value; a click opens the choices
// right below it (inside the card, so nothing is cut off by the sidebar edge), a pick closes it.
//   values: [v, …]   current: v   label: v => text   onPicked: v => …
Column {
    id: dd
    property string title: ""
    property var values: []
    property var current
    property var label: v => String(v)
    property bool open: false
    property int maxVisible: 6
    signal picked(var v)

    width: parent ? parent.width : 200
    spacing: 4

    function same(a, b) { return String(a) === String(b) }

    Rectangle {
        width: dd.width
        height: 32
        radius: 8
        color: hm.containsMouse || dd.open ? "#2f3549" : "#1f2335"
        border.width: 1
        border.color: dd.open ? "#7aa2f7" : "#414868"

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: dd.title
            color: "#565f89"; font.pixelSize: 11
        }
        Text {
            anchors.right: chev.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: dd.current === undefined || dd.current === "" ? "…" : dd.label(dd.current)
            color: "#c0caf5"; font.pixelSize: 12; font.bold: true
        }
        Text {
            id: chev
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(0xF0140)   // chevron-down
            font.family: "JetBrainsMono Nerd Font Mono"
            font.pixelSize: 14
            color: "#a9b1d6"
            rotation: dd.open ? 180 : 0
            Behavior on rotation { NumberAnimation { duration: 160 } }
        }
        MouseArea {
            id: hm
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: dd.open = !dd.open
        }
    }

    // the choices (scrolls when there are many)
    Rectangle {
        visible: dd.open
        width: dd.width
        height: Math.min(dd.values.length, dd.maxVisible) * 28 + 8
        radius: 8
        color: "#16161e"
        border.width: 1
        border.color: "#414868"
        clip: true

        ListView {
            id: lv
            anchors.fill: parent
            anchors.margins: 4
            model: dd.values
            boundsBehavior: Flickable.StopAtBounds
            interactive: dd.values.length > dd.maxVisible
            delegate: Rectangle {
                required property var modelData
                readonly property bool sel: dd.same(modelData, dd.current)
                width: lv.width
                height: 28
                radius: 6
                color: sel ? "#7aa2f7" : (im.containsMouse ? "#2f3549" : "transparent")
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: dd.label(modelData)
                    color: parent.sel ? "#1a1b26" : "#c0caf5"
                    font.pixelSize: 12
                    font.bold: parent.sel
                }
                MouseArea {
                    id: im
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { dd.open = false; if (!dd.same(modelData, dd.current)) dd.picked(modelData) }
                }
            }
            Component.onCompleted: positionViewAtIndex(Math.max(0, dd.values.findIndex(v => dd.same(v, dd.current))), ListView.Center)
        }
    }
}
