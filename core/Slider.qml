import QtQuick

// Pill slider with an icon: <Slider icon="volume_up" value={0..1} onMoved={v => ...}/>
Item {
    id: s
    property string icon: ""
    property real value: 0
    signal moved(real v)
    implicitHeight: 32

    Icon { id: ic; name: s.icon; size: 20; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
    Rectangle {
        id: track
        anchors { left: ic.right; leftMargin: 12; right: parent.right; verticalCenter: parent.verticalCenter }
        height: 12; radius: 6; color: Qt.rgba(1, 1, 1, 0.10)
        Rectangle {
            height: parent.height; radius: 6; color: Theme.accent
            width: Math.max(parent.height, parent.width * Math.max(0, Math.min(1, s.value)))
            Behavior on width { enabled: !ma.pressed; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
        Rectangle {   // handle
            width: 5; height: 22; radius: 2.5; color: Theme.accent
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(parent.width - width, parent.width * s.value - width - 2))
            scale: ma.pressed ? 1.15 : 1
            Behavior on scale { NumberAnimation { duration: 120 } }
        }
    }
    MouseArea {
        id: ma
        anchors { left: track.left; right: track.right; verticalCenter: track.verticalCenter }
        height: 32; cursorShape: Qt.PointingHandCursor
        function set(mx) { s.moved(Math.max(0, Math.min(1, mx / width))); }
        onPressed: m => set(m.x)
        onPositionChanged: m => { if (pressed) set(m.x); }
    }
}
