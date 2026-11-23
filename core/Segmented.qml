import QtQuick

// Segmented choice: <Segmented options={[{l:"Top",v:"top",i:"icon"}]} current="top" onPicked={v => ...}/>
Row {
    id: seg
    property var options: []
    property string current: ""
    property int itemWidth: 96
    signal picked(string v)
    spacing: 6
    Repeater {
        model: seg.options
        delegate: Rectangle {
            required property var modelData
            readonly property bool sel: seg.current === modelData.v
            width: seg.itemWidth; height: 36; radius: 18
            color: sel ? Theme.accent : (ma.containsMouse ? Theme.tileFillHover : Qt.rgba(1, 1, 1, 0.07))
            Behavior on color { ColorAnimation { duration: 160 } }
            Row { anchors.centerIn: parent; spacing: 5
                Icon { visible: !!modelData.i; name: modelData.i || ""; size: 17; color: parent.parent.sel ? "#101218" : Theme.text; anchors.verticalCenter: parent.verticalCenter }
                Text { text: modelData.l; color: parent.parent.sel ? "#101218" : Theme.text; font.family: Theme.font; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter } }
            MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: seg.picked(modelData.v) }
        }
    }
}
