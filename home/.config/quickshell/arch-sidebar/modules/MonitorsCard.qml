import QtQuick
import Quickshell
import Quickshell.Io

// Monitors (Settings page): arrangement map (drag screens, magnetic edges), per-screen on/off,
// resolution, scale, position, primary; automatic switching on hotplug, detect now, saved layouts (autorandr).
// Everything goes through ~/.local/bin/dwm-monitor.
Item {
    id: root

    width: 300
    height: col.implicitHeight

    signal requestClose()

    property var outs: []       // [{ name, on, primary, mode, rate, x, y, modes, model, scale, logical }]
    property var profiles: []   // [{ name, state, isDefault }]
    property bool auto: true

    function refresh() { listP.running = true; profP.running = true; autoP.running = true }
    Component.onCompleted: refresh()
    onVisibleChanged: if (visible) refresh()

    Process {
        id: listP
        command: ["dwm-monitor", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = []
                for (const l of this.text.split("\n")) {
                    const f = l.split("|")
                    if (f.length < 9) continue
                    o.push({ name: f[0], on: f[1] === "1", primary: f[2] === "1", mode: f[3], rate: f[4],
                             x: Number(f[5]), y: Number(f[6]), modes: f[7].split(",").filter(m => m), model: f[8],
                             scale: Number(f[9]) || 100, logical: f[10] || f[3],
                             allModes: (f[11] || "").split(";").filter(x => x).map(x => x.split("@")[0]),
                             rates: root.rateMap(f[11] || ""),
                             rateNow: f[12] && f[12] !== "-" ? f[12] : "" })
                }
                // rebuild the cards only when something changed (an open drop-down stays open)
                if (JSON.stringify(o) !== JSON.stringify(root.outs)) root.outs = o
            }
        }
    }
    Process {
        id: profP
        command: ["dwm-monitor", "profiles"]
        stdout: StdioCollector {
            onStreamFinished: root.profiles = this.text.split("\n").filter(l => l).map(l => {
                const f = l.split("|"); return { name: f[0], state: f[1] || "", isDefault: f[2] === "1" } })
        }
    }
    Process {
        id: autoP
        command: ["dwm-monitor", "auto", "status"]
        stdout: StdioCollector { onStreamFinished: root.auto = this.text.trim() !== "off" }
    }

    Timer { id: refreshSoon; interval: 1200; onTriggered: root.refresh() }
    Timer { interval: 4000; running: root.visible && !map.dragName; repeat: true; onTriggered: root.refresh() }

    function mon(args, close) {
        if (close) root.requestClose()
        Quickshell.execDetached(close ? ["sh", "-c", "sleep 0.3; dwm-monitor " + args.join(" ")]
                                      : ["dwm-monitor"].concat(args))
        refreshSoon.restart()
    }
    // per-screen scale lives in dwm-display (it is saved and re-applied at login)
    function disp(args) {
        Quickshell.execDetached(["dwm-display"].concat(args))
        refreshSoon.restart()
    }
    function wh(m) { const p = (m || "0x0").split("x"); return [Number(p[0]) || 0, Number(p[1]) || 0] }
    // size on the desktop: the scaled (logical) size when the screen is zoomed
    function size(o) { return wh(o.logical && o.logical !== "-" ? o.logical : o.mode) }
    readonly property var scales: [100, 125, 150, 175, 200, 225, 250]
    function hz(r) { return Number(r) + " Hz" }
    // "3840x2160@120.00/60.00;2560x1440@59.95" -> { "3840x2160": ["120.00", "60.00"], … }
    function rateMap(t) {
        const m = {}
        for (const x of t.split(";")) {
            if (!x) continue
            const p = x.split("@")
            m[p[0]] = (p[1] || "").split("/").filter(y => y)
        }
        return m
    }

    // a screen was dropped on the map: show it there until the real layout is read back
    function move(name, x, y) {
        root.outs = root.outs.map(o => o.name === name ? Object.assign({}, o, { x: x, y: y }) : o)
        mon(["set"].concat(root.outs.filter(o => o.on && o.mode !== "-").map(o => o.name + "=" + o.x + "," + o.y)))
    }

    Column {
        id: col
        width: parent.width
        spacing: 10

        // ---------------------------------------------------------------- arrangement map
        // Drag a screen to move it; it snaps (magnet) to the other screens' edges and lines up with
        // their edges and centres. Released, the layout is applied (dwm-monitor set): overlaps are
        // pushed apart and a screen left floating sticks to the nearest one.
        Rectangle {
            id: map
            width: parent.width
            height: 160
            radius: 12
            color: "#16161e"
            border.width: 1
            border.color: map.dragName ? "#7aa2f7" : "#414868"
            clip: true

            readonly property var active: root.outs.filter(o => o.on && o.mode !== "-")
            readonly property real minX: Math.min(...active.map(o => o.x), 0)
            readonly property real minY: Math.min(...active.map(o => o.y), 0)
            readonly property real maxX: Math.max(...active.map(o => o.x + root.size(o)[0]), 1)
            readonly property real maxY: Math.max(...active.map(o => o.y + root.size(o)[1]), 1)
            // room around the screens to drag into
            readonly property real k: Math.min((width - 24) / (maxX - minX), (height - 24) / (maxY - minY)) * 0.8
            readonly property real ox: (width - (maxX - minX) * k) / 2
            readonly property real oy: (height - (maxY - minY) * k) / 2

            // drag state (real pixels)
            property string dragName: ""
            property real dragX: 0
            property real dragY: 0
            property bool dragBad: false
            readonly property real magnet: 14 / k   // 14 px on the map

            function pos(o) { return o.name === dragName ? [dragX, dragY] : [o.x, o.y] }
            function overlaps(ax, ay, aw, ah, b) {
                const [bw, bh] = root.size(b)
                return Math.min(ax + aw, b.x + bw) - Math.max(ax, b.x) > 0 && Math.min(ay + ah, b.y + bh) - Math.max(ay, b.y) > 0
            }
            // magnet: per axis, the closest of "touching" and "lined up" spots within reach
            function snap(o, x, y) {
                const [w, h] = root.size(o)
                const others = active.filter(b => b.name !== o.name)
                let bx = x, by = y, dx = magnet, dy = magnet
                for (const b of others) {
                    const [bw, bh] = root.size(b)
                    for (const c of [b.x - w, b.x + bw, b.x, b.x + bw - w, b.x + (bw - w) / 2])
                        if (Math.abs(c - x) < dx) { dx = Math.abs(c - x); bx = c }
                    for (const c of [b.y - h, b.y + bh, b.y, b.y + bh - h, b.y + (bh - h) / 2])
                        if (Math.abs(c - y) < dy) { dy = Math.abs(c - y); by = c }
                }
                return [Math.round(bx), Math.round(by)]
            }

            Repeater {
                model: map.active
                Rectangle {
                    id: scr
                    required property var modelData
                    readonly property bool dragging: map.dragName === modelData.name
                    x: map.ox + (map.pos(modelData)[0] - map.minX) * map.k
                    y: map.oy + (map.pos(modelData)[1] - map.minY) * map.k
                    z: dragging ? 2 : 1
                    width: root.size(modelData)[0] * map.k - 3
                    height: root.size(modelData)[1] * map.k - 3
                    radius: 5
                    color: dragging ? (map.dragBad ? "#3b2030" : "#2f3f6b") : (modelData.primary ? "#2f3f6b" : "#24283b")
                    opacity: dragging ? 0.92 : 1
                    border.width: modelData.primary || dragging ? 2 : 1
                    border.color: dragging ? (map.dragBad ? "#f7768e" : "#9ece6a")
                                           : (modelData.primary ? "#7aa2f7" : (sm.containsMouse ? "#a9b1d6" : "#565f89"))
                    Column {
                        anchors.centerIn: parent
                        spacing: 1
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: scr.modelData.name; color: "#c0caf5"; font.pixelSize: 9; font.bold: true }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: scr.modelData.mode + (scr.modelData.scale !== 100 ? " · " + scr.modelData.scale + "%" : "")
                            color: "#a9b1d6"; font.pixelSize: 8
                        }
                    }
                    MouseArea {
                        id: sm
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: scr.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        preventStealing: true   // the settings page scrolls (Flickable): keep the drag
                        property point start
                        property bool moved: false
                        onPressed: m => {
                            const p = mapToItem(map, m.x, m.y)
                            start = Qt.point(p.x, p.y); moved = false
                            map.dragX = scr.modelData.x; map.dragY = scr.modelData.y; map.dragBad = false
                            map.dragName = scr.modelData.name
                        }
                        onPositionChanged: m => {
                            if (!pressed) return
                            const p = mapToItem(map, m.x, m.y)
                            if (!moved && Math.abs(p.x - start.x) + Math.abs(p.y - start.y) < 4) return
                            moved = true
                            const s = map.snap(scr.modelData, scr.modelData.x + (p.x - start.x) / map.k,
                                                              scr.modelData.y + (p.y - start.y) / map.k)
                            map.dragX = s[0]; map.dragY = s[1]
                            const [w, h] = root.size(scr.modelData)
                            map.dragBad = map.active.some(b => b.name !== scr.modelData.name && (b.x !== s[0] || b.y !== s[1])
                                                              && map.overlaps(s[0], s[1], w, h, b))
                        }
                        onReleased: {
                            const name = scr.modelData.name, nx = map.dragX, ny = map.dragY
                            const go = moved && (nx !== scr.modelData.x || ny !== scr.modelData.y)
                            map.dragName = ""
                            if (go) Qt.callLater(root.move, name, nx, ny)   // after this handler: the map is rebuilt
                        }
                        onCanceled: map.dragName = ""
                    }
                }
            }
            Text {
                visible: map.active.length === 0
                anchors.centerIn: parent
                text: "…"
                color: "#565f89"
            }
            Text {
                visible: map.active.length > 1 && !map.dragName
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                anchors.horizontalCenter: parent.horizontalCenter
                text: "drag a screen to move it"
                color: "#414868"; font.pixelSize: 9
            }
        }

        // ---------------------------------------------------------------- automatic + actions
        Row {
            width: parent.width
            spacing: 8
            Column {
                width: parent.width - 58 - 8
                anchors.verticalCenter: parent.verticalCenter
                Text { text: "Automatic"; color: "#c0caf5"; font.pixelSize: 13; font.bold: true }
                Text {
                    width: parent.width
                    text: "plug in a screen: saved layout, or side by side"
                    color: "#565f89"; font.pixelSize: 9; elide: Text.ElideRight
                }
            }
            Switch2 { on: root.auto; onToggled: { root.auto = !root.auto; root.mon(["auto", root.auto ? "on" : "off"]) } }
        }

        Row {
            id: acts
            width: parent.width
            spacing: 6
            readonly property real cellWidth: (width - spacing) / 2
            ActionButton { width: acts.cellWidth; implicitHeight: 52; glyph: 0xF0379; label: "Detect now"; onClicked: root.mon(["detect"]) }
            ActionButton { width: acts.cellWidth; implicitHeight: 52; glyph: 0xF0193; label: "Save layout…"; accent: "#9ece6a"; onClicked: root.mon(["save"], true) }
        }

        // ---------------------------------------------------------------- one card per connected screen
        Repeater {
            model: root.outs
            Rectangle {
                id: mc
                required property var modelData
                width: col.width
                height: mcol.implicitHeight + 24
                radius: 12
                color: "#1f2335"
                border.width: 1
                border.color: modelData.primary ? "#7aa2f7" : "#414868"

                Column {
                    id: mcol
                    x: 12
                    y: 12
                    width: parent.width - 24
                    spacing: 8

                    Row {
                        width: parent.width
                        spacing: 10
                        Text {
                            text: String.fromCodePoint(mc.modelData.name.startsWith("eDP") ? 0xF0322 : 0xF0379)  // laptop / monitor
                            font.family: "JetBrainsMono Nerd Font Mono"
                            font.pixelSize: 20
                            color: mc.modelData.on ? "#7aa2f7" : "#565f89"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Column {
                            width: parent.width - 30 - 58 - 20
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                width: parent.width
                                text: mc.modelData.model
                                color: "#c0caf5"; font.pixelSize: 13; font.bold: true; elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: mc.modelData.name + (mc.modelData.on ? "  ·  " + mc.modelData.mode + " @ " + mc.modelData.rate + " Hz"
                                                                  + (mc.modelData.scale !== 100 ? "  ·  " + mc.modelData.scale + "%" : "") : "  ·  off")
                                      + (mc.modelData.primary ? "  ·  primary" : "")
                                color: mc.modelData.primary ? "#7aa2f7" : "#565f89"; font.pixelSize: 10; elide: Text.ElideRight
                            }
                        }
                        Switch2 {
                            anchors.verticalCenter: parent.verticalCenter
                            on: mc.modelData.on
                            onToggled: root.mon([mc.modelData.on ? "off" : "on", mc.modelData.name])
                        }
                    }

                    // resolution (the highest refresh rate it has), refresh rate, scale: drop-downs
                    Dropdown {
                        visible: mc.modelData.on
                        title: "Resolution"
                        values: mc.modelData.allModes && mc.modelData.allModes.length ? mc.modelData.allModes : mc.modelData.modes
                        current: mc.modelData.mode
                        onPicked: v => root.mon(["mode", mc.modelData.name, v])
                    }
                    Dropdown {
                        visible: mc.modelData.on && (mc.modelData.rates[mc.modelData.mode] || []).length > 0
                        title: "Refresh rate"
                        values: mc.modelData.rates[mc.modelData.mode] || []
                        current: mc.modelData.rateNow
                        label: v => root.hz(v)
                        onPicked: v => root.mon(["mode", mc.modelData.name, mc.modelData.mode, v])
                    }
                    // scale (zoom) of this screen only: bar, windows and menus on it
                    Dropdown {
                        visible: mc.modelData.on
                        title: "Scale"
                        values: root.scales
                        current: mc.modelData.scale
                        label: v => v + "%" + (v === 100 ? "  (none)" : "")
                        onPicked: v => root.disp(["scale", String(v), mc.modelData.name])
                    }

                    // position relative to the primary
                    ChipRow {
                        visible: mc.modelData.on && !mc.modelData.primary
                        values: ["left", "right", "above", "below", "mirror"]
                        current: ""
                        label: v => v
                        onPicked: v => root.mon(["place", mc.modelData.name, v])
                    }

                    Rectangle {
                        visible: mc.modelData.on && !mc.modelData.primary
                        width: parent.width
                        height: 28
                        radius: 8
                        color: pm.containsMouse ? "#2f3549" : "transparent"
                        border.width: 1
                        border.color: "#414868"
                        Text { anchors.centerIn: parent; text: "Make primary (bar status · sidebar)"; color: "#a9b1d6"; font.pixelSize: 10 }
                        MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.mon(["primary", mc.modelData.name]) }
                    }
                }
            }
        }

        // ---------------------------------------------------------------- saved layouts
        Text {
            visible: root.profiles.length > 0
            text: "Saved layouts"
            color: "#c0caf5"; font.pixelSize: 13; font.bold: true
        }
        Repeater {
            model: root.profiles
            Rectangle {
                required property var modelData
                width: col.width
                height: 36
                radius: 9
                color: "#1f2335"
                border.width: 1
                border.color: modelData.state === "current" ? "#7aa2f7" : "#414868"
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name + (modelData.isDefault ? "  ·  default" : "") + (modelData.state ? "  ·  " + modelData.state : "")
                    color: modelData.state === "current" ? "#7aa2f7" : "#c0caf5"
                    font.pixelSize: 12
                }
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    // default layout: loaded at login (click again: no default)
                    Rectangle {
                        width: 24; height: 24; radius: 7
                        color: sm2.containsMouse ? "#e0af68" : "#24283b"
                        Text {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(modelData.isDefault ? 0xF04CE : 0xF04D2)   // star / star-outline
                            font.family: "JetBrainsMono Nerd Font Mono"; font.pixelSize: 13
                            color: sm2.containsMouse ? "#1a1b26" : "#e0af68"
                        }
                        MouseArea {
                            id: sm2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.mon(["default", modelData.isDefault ? "off" : modelData.name])
                        }
                    }
                    Rectangle {
                        width: 54; height: 24; radius: 7
                        color: am.containsMouse ? "#7aa2f7" : "#24283b"
                        Text { anchors.centerIn: parent; text: "Apply"; font.pixelSize: 10; font.bold: true; color: am.containsMouse ? "#1a1b26" : "#7aa2f7" }
                        MouseArea { id: am; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.mon(["load", modelData.name]) }
                    }
                    Rectangle {
                        width: 24; height: 24; radius: 7
                        color: dm.containsMouse ? "#f7768e" : "#24283b"
                        Text { anchors.centerIn: parent; text: String.fromCodePoint(0xF01B4); font.family: "JetBrainsMono Nerd Font Mono"; font.pixelSize: 12; color: dm.containsMouse ? "#1a1b26" : "#f7768e" }
                        MouseArea { id: dm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.mon(["delete", modelData.name]) }
                    }
                }
            }
        }
        Text {
            width: parent.width
            text: "Save a layout once for each setup (laptop only, desk, TV…). When the same screens are plugged in again it is applied automatically. ★ = the default: loaded at every login when its screens are connected (save it again with the same name after changing the layout)."
            color: "#565f89"; font.pixelSize: 10; wrapMode: Text.WordWrap
        }
    }
}
