import QtQuick
import Quickshell
import Quickshell.Io

// Display settings as an accordion (like the Wi-Fi networks list):
// collapsed = one-line summary, expanded = scale (per screen), bar size, font size, resolution.
// Everything goes through ~/.local/bin/dwm-display.
Item {
    id: root

    width: 300
    height: card.height

    signal requestClose()

    property bool expanded: false
    property int scale: 100            // the selected screen's scale
    property var screens: []           // [{ name, scale }] from "scales=out:pct,…"
    property string screen: ""         // selected screen ("" = the primary, first in the list)
    property real barScale: 1.0
    property int fontSize: 0
    property string resolution: ""
    property var modes: []             // the primary's resolutions
    readonly property var scales: [100, 125, 150, 175, 200, 225, 250]
    readonly property var barScales: [1.0, 1.15, 1.3, 1.5, 1.75]

    function refresh() { statusProcess.running = true }

    Process {
        id: statusProcess
        running: true
        command: ["dwm-display", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const kv of this.text.trim().split(" ")) {
                    const [k, v] = kv.split("=")
                    if (k === "scales") root.screens = v.split(",").filter(x => x).map(x => {
                        const i = x.lastIndexOf(":"); return { name: x.slice(0, i), scale: Number(x.slice(i + 1)) || 100 } })
                    else if (k === "scale" && !root.screen) root.scale = Number(v)
                    else if (k === "bar") root.barScale = Number(v) || 1
                    else if (k === "font") root.fontSize = Number(v)
                    else if (k === "res") root.resolution = v
                    else if (k === "modes") root.modes = v.split(",").filter(x => x)
                }
                const sel = root.screens.find(x => x.name === root.screen)
                if (sel) root.scale = sel.scale
                else root.screen = ""
            }
        }
    }

    Process {
        id: runProcess
        onExited: root.refresh()
    }

    function run(args) {
        runProcess.command = ["dwm-display"].concat(args)
        runProcess.running = true
    }

    Rectangle {
        id: card
        width: parent.width
        height: header.height + (root.expanded ? body.implicitHeight + 14 : 0) + 28
        radius: 15
        color: "#24283b"
        clip: true
        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        // ---------------------------------------------------------------- header (click to expand)
        Item {
            id: header
            x: 14
            y: 14
            width: parent.width - 28
            height: 40

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Text { text: "Screen & bar"; color: "#c0caf5"; font.pixelSize: 14; font.bold: true }
                Text {
                    text: (root.screens.length > 1 ? root.screens.map(x => x.scale + "%").join(" ") : "screen " + root.scale + "%") + "  ·  bar " + root.barScale.toFixed(2).replace(/\.?0+$/, "") + "×  ·  " + (root.resolution || "…")
                    color: "#7aa2f7"
                    font.pixelSize: 11
                    width: header.width - 44
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                radius: 8
                color: hm.containsMouse ? "#2f3549" : "#1f2335"
                border.width: 1
                border.color: "#414868"
                Text {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(0xF0140)   // chevron-down
                    font.family: "JetBrainsMono Nerd Font Mono"
                    font.pixelSize: 16
                    color: "#a9b1d6"
                    rotation: root.expanded ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                }
            }

            MouseArea {
                id: hm
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.expanded = !root.expanded; if (root.expanded) root.refresh() }
            }
        }

        // ---------------------------------------------------------------- body
        Column {
            id: body
            x: 14
            anchors.top: header.bottom
            anchors.topMargin: 14
            width: parent.width - 28
            spacing: 10
            opacity: root.expanded ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 180 } }

            Rectangle { width: parent.width; height: 1; color: "#414868" }

            RowTitle { title: "Screen scale"; value: root.scale + "%" }
            // several screens: pick which one (each has its own scale)
            Dropdown {
                visible: root.screens.length > 1
                title: "Screen"
                values: root.screens.map(x => x.name)
                current: root.screen || (root.screens[0] ? root.screens[0].name : "")
                onPicked: v => { root.screen = v; const x = root.screens.find(s => s.name === v); if (x) root.scale = x.scale }
            }
            Dropdown {
                title: "Scale"
                values: root.scales
                current: root.scale
                label: v => v + "%"
                onPicked: v => {
                    root.scale = v
                    root.run(["scale", String(v)].concat(root.screen ? [root.screen] : []))
                }
            }
            Text {
                width: parent.width; wrapMode: Text.WordWrap; color: "#565f89"; font.pixelSize: 10
                text: root.screens.length > 1
                      ? "Only the selected screen: its bar, windows and menus get bigger; the other screens stay as they are and stay attached to it."
                      : "Everything gets bigger at once: bar, windows, menus, this sidebar. Instant."
            }

            RowTitle { title: "Bar size"; value: root.barScale.toFixed(2).replace(/\.?0+$/, "") + "×" }
            ChipRow {
                values: root.barScales
                current: root.barScale
                label: v => Math.round(v * 100) + "%"
                onPicked: v => { root.barScale = v; root.run(["bar", String(v)]) }
            }
            Text { width: parent.width; wrapMode: Text.WordWrap; text: "Only the dwm bar, on every screen, on top of each screen's scale: its text, icons and height (dwm restarts in place, windows stay)."; color: "#565f89"; font.pixelSize: 10 }

            // resolution of the primary screen (asks to keep it, reverts after 15 s)
            Dropdown {
                title: "Resolution"
                values: root.modes.length ? root.modes : [root.resolution]
                current: root.resolution
                onPicked: v => {
                    root.requestClose()
                    Quickshell.execDetached(["sh", "-c", "sleep 0.3; dwm-display res " + v])
                }
            }

            ResetButton {
                what: "display"
                onConfirmed: { root.run(["reset"]) }
            }
        }
    }

    // refresh after an external change (rofi menu, keybinding)
    Timer { interval: 5000; running: true; repeat: true; onTriggered: root.refresh() }
}
