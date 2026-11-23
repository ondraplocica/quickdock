import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../core"

Tile {
    id: w
    interactive: false
    readonly property var win: ToplevelManager.activeToplevel
    readonly property bool has: win !== null && win !== undefined
    readonly property var entry: has ? DesktopEntries.heuristicLookup(win.appId) : null
    readonly property real maxW: config.maxWidth ?? 260
    implicitWidth: has ? Math.min(maxW, row.implicitWidth + 24) : 0
    opacity: has ? 1 : 0
    clip: true
    Behavior on opacity { NumberAnimation { duration: 200 } }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        x: 12; spacing: 8
        Image { width: 24; height: 24; anchors.verticalCenter: parent.verticalCenter; sourceSize: Qt.size(96, 96); smooth: true; mipmap: true
            source: w.entry ? Quickshell.iconPath(w.entry.icon, true) : ""; visible: status === Image.Ready }
        Column { anchors.verticalCenter: parent.verticalCenter
            Text { id: ttl; width: Math.min(implicitWidth, w.maxW - 60); elide: Text.ElideRight
                text: w.has ? (w.win.title || w.win.appId) : ""
                color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                onTextChanged: swap.restart()
                SequentialAnimation { id: swap
                    NumberAnimation { target: ttl; property: "opacity"; to: 0.3; duration: 80 }
                    NumberAnimation { target: ttl; property: "opacity"; to: 1; duration: 200 } } }
            Text { textFormat: Text.PlainText; width: Math.min(implicitWidth, w.maxW - 60); elide: Text.ElideRight
                text: w.entry ? w.entry.name : (w.has ? w.win.appId : ""); color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10 }
        }
    }
}
