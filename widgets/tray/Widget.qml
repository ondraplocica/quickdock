import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../../core"

Tile {
    id: w
    interactive: false
    readonly property var items: SystemTray.items.values
    property var activeMenu: null
    Item { id: menuGhost; readonly property real extra: Dock.popGap / Dock.uiScale
        y: Dock.popBelow ? 0 : -extra; width: 1; height: w.height + extra }
    // One menu anchor on a stable item (anchoring to per-icon delegates crashes when icons come and go).
    QsMenuAnchor { id: trayMenu; menu: w.activeMenu; anchor.item: menuGhost; anchor.edges: Dock.popBelow ? Edges.Bottom : Edges.Top; anchor.gravity: Dock.popBelow ? Edges.Bottom : Edges.Top }
    implicitWidth: items.length ? row.implicitWidth + 16 : 0
    opacity: items.length ? 1 : 0
    clip: true
    Behavior on opacity { NumberAnimation { duration: 200 } }

    Row {
        id: row
        anchors.centerIn: parent; spacing: 6
        Repeater {
            model: w.items
            delegate: Item {
                id: ti
                required property var modelData
                width: 28; height: 28
                Image { id: ic; anchors.centerIn: parent; width: 20; height: 20; sourceSize: Qt.size(96, 96); smooth: true; mipmap: true
                    source: modelData.icon
                    scale: ma.containsMouse ? 1.2 : 1
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } } }
                MouseArea {
                    id: ma
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: m => {
                        if (m.button === Qt.MiddleButton) modelData.secondaryActivate();
                        else if (m.button === Qt.RightButton || modelData.onlyMenu) { if (modelData.hasMenu) { w.activeMenu = modelData.menu; menuGhost.x = ti.mapToItem(w, ti.width / 2, 0).x; trayMenu.open(); } }
                        else modelData.activate();
                    }
                }
            }
        }
    }
}
