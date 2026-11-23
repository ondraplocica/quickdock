import QtQuick
import Quickshell.Hyprland
import "../../core"

Tile {
    id: w
    interactive: false
    implicitWidth: row.implicitWidth + 16
    readonly property int count: config.count ?? 10
    readonly property int focusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    function exists(id) { return Hyprland.workspaces.values.some(x => x.id === id); }
    WheelHandler { onWheel: e => Hyprland.dispatch("workspace " + (e.angleDelta.y > 0 ? "e-1" : "e+1")) }

    Row {
        id: row
        anchors.centerIn: parent; spacing: 4
        Repeater {
            model: w.count
            delegate: Rectangle {
                required property int index
                readonly property int wid: index + 1
                readonly property bool cur: w.focusedId === wid
                readonly property bool occ: w.exists(wid)
                width: cur ? 30 : 22; height: 22; radius: 11
                color: cur ? Theme.accent : (m.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : (occ ? Qt.rgba(1, 1, 1, 0.10) : "transparent"))
                border.width: occ || cur ? 0 : 1; border.color: Theme.hairline
                Behavior on width { NumberAnimation { duration: Theme.medium; easing.type: Easing.OutBack } }
                Behavior on color { ColorAnimation { duration: 160 } }
                Text { anchors.centerIn: parent; text: wid; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                    color: cur ? "#101218" : (occ ? Theme.text : Theme.textDim) }
                MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("workspace " + wid) }
            }
        }
    }
}
