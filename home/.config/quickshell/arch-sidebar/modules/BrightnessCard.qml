import QtQuick
import Quickshell
import Quickshell.Io

// Brightness of every screen, each with its own slider: the laptop panel (backlight) and external
// monitors (DDC/CI). With several screens an "All screens" slider moves them together.
// Everything goes through ~/.local/bin/dwm-bright (it caches monitor values: DDC is slow).
Item {
    id: root

    width: 300
    height: card.height

    property var screens: []     // [{ id, kind, name }]  (rebuilt only when screens come or go)
    property var values: ({})    // id -> percent (-1 = unknown)
    property bool busy: false    // first detection running
    property bool dragging: false

    function load(text) {
        const s = [], v = {}
        for (const l of text.split("\n")) {
            const f = l.split("|")
            if (f.length < 4) continue
            s.push({ id: f[0], kind: f[1], name: f[2] })
            v[f[0]] = f[3] === "?" ? -1 : Number(f[3])
        }
        if (JSON.stringify(s) !== JSON.stringify(root.screens)) root.screens = s
        if (!root.dragging && !setP.running && !root.pending) root.values = v
    }

    Process {
        id: listP
        command: ["dwm-bright", "list"]
        stdout: StdioCollector { onStreamFinished: root.load(this.text) }
    }
    // re-detect monitors and re-read them (slow, ~1 s): when the sidebar opens
    Process {
        id: refreshP
        command: ["dwm-bright", "refresh"]
        onRunningChanged: root.busy = running && root.screens.length === 0
        stdout: StdioCollector { onStreamFinished: root.load(this.text) }
    }
    Component.onCompleted: refreshP.running = true
    onVisibleChanged: if (visible && !refreshP.running) refreshP.running = true
    Timer { interval: 5000; running: root.visible; repeat: true; onTriggered: if (!refreshP.running) listP.running = true }

    // one write at a time; while dragging only the latest value is sent
    property var pending: null   // [id, pct]
    Process {
        id: setP
        onRunningChanged: if (!running && root.pending) root.flush()
    }
    function send(id, pct) { pending = [id, String(Math.round(pct))]; if (!setP.running) flush() }
    function flush() {
        const p = pending; pending = null
        setP.command = ["dwm-bright", "set"].concat(p)
        setP.running = true
    }
    function setLocal(id, pct) {
        const v = Object.assign({}, root.values)
        for (const s of root.screens) if (id === "all" || s.id === id) v[s.id] = pct
        root.values = v
    }
    readonly property real average: {
        const v = screens.map(s => values[s.id]).filter(x => x >= 0)
        return v.length ? v.reduce((a, x) => a + x, 0) / v.length : 50
    }

    component Slider: Item {
        id: sl
        property string title
        property string sub
        property real value: 50          // 0-100, -1 = unknown
        property color accent: "#e0af68"
        signal moved(real v)
        width: parent.width
        height: 44

        Row {
            width: parent.width
            Text {
                width: parent.width - pct.width
                text: sl.title + (sl.sub ? "  <font color=\"#565f89\">" + sl.sub + "</font>" : "")
                textFormat: Text.StyledText
                color: "#c0caf5"; font.pixelSize: 12; font.bold: true; elide: Text.ElideRight
            }
            Text { id: pct; text: sl.value < 0 ? "?" : Math.round(sl.value) + "%"; color: "#7aa2f7"; font.pixelSize: 12 }
        }
        Rectangle {
            id: track
            y: 26
            width: parent.width
            height: 9
            radius: 5
            color: "#414868"
            Rectangle { width: track.width * Math.max(0, sl.value) / 100; height: parent.height; radius: 5; color: sl.accent }
            Rectangle {
                width: 17; height: 17; radius: 9
                color: "#c0caf5"
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(track.width - width, track.width * Math.max(0, sl.value) / 100 - width / 2))
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                preventStealing: true
                cursorShape: Qt.PointingHandCursor
                function at(x) { return Math.max(1, Math.min(100, (x - 8) / track.width * 100)) }
                onPressed: m => { root.dragging = true; sl.moved(at(m.x)) }
                onPositionChanged: m => { if (pressed) sl.moved(at(m.x)) }
                onReleased: root.dragging = false
                onCanceled: root.dragging = false
            }
        }
    }

    Rectangle {
        id: card
        width: parent.width
        height: col.implicitHeight + 28
        radius: 15
        color: "#24283b"

        Column {
            id: col
            x: 14; y: 14
            width: parent.width - 28
            spacing: 10

            Text {
                text: "Brightness"
                color: "#c0caf5"; font.pixelSize: 14; font.bold: true
            }

            Slider {
                visible: root.screens.length > 1
                title: "All screens"
                accent: "#ff9e64"
                value: root.average
                onMoved: v => { root.setLocal("all", v); root.send("all", v) }
            }
            Rectangle { visible: root.screens.length > 1; width: parent.width; height: 1; color: "#414868" }

            Repeater {
                model: root.screens
                Slider {
                    required property var modelData
                    title: modelData.name
                    sub: modelData.kind === "ddc" ? modelData.id.replace("DisplayPort-", "DP-").replace("HDMI-A-", "HDMI-") : ""
                    value: root.values[modelData.id] ?? -1
                    onMoved: v => { root.setLocal(modelData.id, v); root.send(modelData.id, v) }
                }
            }

            Text {
                visible: root.screens.length === 0
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#565f89"; font.pixelSize: 10
                text: root.busy ? "Looking for screens…"
                    : "No screen whose brightness can be changed. External monitors need ddcutil, the i2c-dev module and DDC/CI on in the monitor's menu: run  dwm-bright doctor  in a terminal."
            }
        }
    }
}
