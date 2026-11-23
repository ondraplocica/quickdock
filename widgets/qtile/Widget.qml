import QtQuick
import "../../core"

// Dock version of a quick-settings tile. Instance id "qtile:<item>" where <item> is one of night, dark, vpn, awake
// (state + action come from core/Quick.qml, so this and the quick panel always agree).
Tile {
    id: w
    implicitWidth: Theme.tileHeight
    readonly property string item: instanceId.indexOf(":") >= 0 ? instanceId.split(":")[1] : ""
    readonly property var meta: Quick.catalog[item] || ({ label: item, icon: "help" })
    readonly property bool on: Quick.isOn(item)
    active: on
    function toggle() { Quick.toggle(item); }
    onClicked: toggle()

    Icon {
        id: ic
        anchors.centerIn: parent
        name: w.meta.icon; size: 24
        filled: w.on
        color: w.on ? Theme.accent : Theme.text
        Behavior on color { ColorAnimation { duration: 200 } }
        onNameChanged: pop.restart()
        SequentialAnimation { id: pop
            NumberAnimation { target: ic; property: "scale"; to: 1.18; duration: 110; easing.type: Easing.OutQuad }
            NumberAnimation { target: ic; property: "scale"; to: 1; duration: 220; easing.type: Easing.OutBack } }
    }
    onOnChanged: pop.restart()
}
