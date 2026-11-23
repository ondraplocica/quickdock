import QtQuick

// Quick-settings tile. style "status": icon box lights up when on (Ethernet, Bluetooth...).
// style "toggle": whole tile fills with the accent when on (Night Mode, Dark Mode...).
Rectangle {
    id: t
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool on: false
    property string style: "status"
    property bool dimmed: false
    property bool hasMenu: false          // shows a chevron button (e.g. device picker)
    property bool menuOpen: false
    signal menuClicked()
    signal clicked()
    signal rightClicked()

    readonly property bool filled: style === "toggle" && on
    implicitHeight: 58
    radius: 20
    color: filled ? Theme.accent : (ma.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.05))
    opacity: dimmed ? 0.35 : 1
    scale: ma.pressed ? 0.97 : 1
    Behavior on color { ColorAnimation { duration: 160 } }
    Behavior on opacity { NumberAnimation { duration: 160 } }
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

    Rectangle {   // icon box
        id: box
        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
        width: 42; height: 42; radius: 14
        color: t.style === "status" ? (t.on ? Theme.accent : Qt.rgba(1, 1, 1, 0.07)) : "transparent"
        Behavior on color { ColorAnimation { duration: 160 } }
        Icon { anchors.centerIn: parent; name: t.icon; size: 22
            color: t.filled ? "#101218" : (t.style === "status" && t.on ? "#101218" : (t.style === "toggle" ? Theme.accent : Theme.text)) }
    }
    Column {
        anchors { left: box.right; leftMargin: 12; right: parent.right; rightMargin: t.hasMenu ? 42 : 10; verticalCenter: parent.verticalCenter }
        Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: t.title
            color: t.filled ? "#101218" : Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
        Text { textFormat: Text.PlainText; visible: t.subtitle !== ""; width: parent.width; elide: Text.ElideRight; text: t.subtitle
            color: t.filled ? Qt.rgba(0.06, 0.07, 0.09, 0.7) : Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
    }
    MouseArea {
        id: ma
        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: m => { if (m.button === Qt.RightButton) t.rightClicked(); else t.clicked(); }
    }
    Rectangle {   // chevron
        visible: t.hasMenu
        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        width: 28; height: 28; radius: 14
        color: cm.containsMouse || t.menuOpen ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
        Behavior on color { ColorAnimation { duration: 140 } }
        Icon { anchors.centerIn: parent; name: "expand_more"; size: 20; color: Theme.text
            rotation: t.menuOpen ? 180 : 0
            Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } } }
        MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: t.menuClicked() }
    }
}
