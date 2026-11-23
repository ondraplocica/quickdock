import QtQuick

// Panel slider (Material You): a tonal track with a flat primary-colour fill; the icon sits inside the fill at the left.
// Clicking the icon emits iconClicked() (e.g. mute); dragging anywhere else sets the value (0..1).
Item {
    id: s
    property string icon: ""
    property real value: 0
    property bool dim: false          // e.g. muted
    signal moved(real v)
    signal iconClicked()
    implicitHeight: 44
    readonly property real fillW: Math.max(height, width * Math.max(0, Math.min(1, value)))

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: QsStyle.trackFill
        clip: true
        Rectangle {
            id: fill
            height: parent.height; radius: parent.radius
            opacity: s.dim ? 0.45 : 1
            width: s.fillW
            color: QsStyle.sliderFill
            Behavior on width { enabled: !drag.pressed; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }
    }
    Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 20; name: s.icon; size: 20
        color: s.fillW > 38 && !s.dim ? QsStyle.onAccent : QsStyle.text; horizontalAlignment: Text.AlignHCenter }
    MouseArea {
        id: drag
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
        function set(mx) { s.moved(Math.max(0, Math.min(1, mx / width))); }
        onPressed: m => { if (m.x > 42) set(m.x); }
        onPositionChanged: m => { if (pressed && m.x > 6) set(m.x); }
        onClicked: m => { if (m.x <= 42) s.iconClicked(); }
    }
}
