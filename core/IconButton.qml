import QtQuick

// Round icon button used in panel headers.
Rectangle {
    id: b
    property string icon: ""
    property bool active: false
    signal clicked()
    width: 38; height: 38; radius: 19
    color: active ? Theme.accent : (ma.containsMouse ? Theme.tileFillHover : "transparent")
    scale: ma.pressed ? 0.9 : 1
    Behavior on color { ColorAnimation { duration: 140 } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
    Icon { anchors.centerIn: parent; name: b.icon; size: 20; color: b.active ? "#101218" : Theme.text }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
}
