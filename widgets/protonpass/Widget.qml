import QtQuick
import "../../core"

// Shows/hides the Proton Pass window. The action and the focus auto-hide hook live in core/Quick.qml.
Tile {
    id: w
    implicitWidth: Theme.tileHeight
    function toggle() { Quick.toggle("protonpass"); }
    onClicked: toggle()
    Icon { anchors.centerIn: parent; name: "key"; size: 24 }
}
