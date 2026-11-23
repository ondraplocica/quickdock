import QtQuick
import Quickshell
import "../../core"

Tile {
    id: w
    implicitWidth: row.implicitWidth + 24
    property int totalSec: 25 * 60
    property int remaining: totalSec
    property bool running: false
    property string label: "Focus"
    readonly property real progress: totalSec > 0 ? 1 - remaining / totalSec : 0
    active: running
    function fmt(s) { const m = Math.floor(s / 60), r = s % 60; return (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r; }
    function preset(min, name) { running = false; label = name; totalSec = min * 60; remaining = totalSec; }
    function reset() { running = false; remaining = totalSec; }
    function start() { if (remaining > 0) running = !running; else reset(); }
    function toggle() { pop.open = !pop.open; }
    onClicked: toggle()
    TapHandler { acceptedButtons: Qt.RightButton; onTapped: w.start() }
    Timer { interval: 1000; repeat: true; running: w.running
        onTriggered: { w.remaining -= 1; if (w.remaining <= 0) { w.running = false;
            Quickshell.execDetached(["notify-send", "-a", "Focus Timer", w.label + " finished", "Time for a break."]); } } }

    Row { id: row; anchors.centerIn: parent; spacing: 8
        Ring { anchors.verticalCenter: parent.verticalCenter; size: 24; thickness: 3.5; value: w.progress }
        Text { anchors.verticalCenter: parent.verticalCenter; text: w.fmt(w.remaining); font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold
            color: w.running ? Theme.accent : Theme.text } }

    Popover {
        id: pop
        target: w
        panelWidth: 290
        panelHeight: 330
        Column { anchors { fill: parent; margins: 16 } spacing: 14
            Item { width: parent.width; height: 170
                Ring { anchors.centerIn: parent; size: 160; thickness: 10; value: w.progress }
                Column { anchors.centerIn: parent; spacing: 2
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: w.fmt(w.remaining); color: Theme.text; font.family: Theme.font; font.pixelSize: 34; font.weight: Font.DemiBold }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: w.label; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 } } }
            Row { spacing: 8; anchors.horizontalCenter: parent.horizontalCenter
                Repeater { model: [ { m: 25, n: "Focus" }, { m: 5, n: "Short break" }, { m: 15, n: "Long break" } ]
                    delegate: Rectangle { required property var modelData
                        readonly property bool sel: w.label === modelData.n
                        width: 82; height: 32; radius: 16; color: sel ? Theme.accent : Theme.tileFill
                        scale: pm.pressed ? 0.94 : (pm.containsMouse ? 1.04 : 1)
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                        Behavior on color { ColorAnimation { duration: 200 } }
                        Text { anchors.centerIn: parent; text: modelData.m + " min"; color: sel ? "#101218" : Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                        MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.preset(modelData.m, modelData.n) } } } }
            Row { spacing: 8; anchors.horizontalCenter: parent.horizontalCenter
                Rectangle { width: 124; height: 40; radius: 20; color: Theme.accent
                    scale: sm.pressed ? 0.94 : (sm.containsMouse ? 1.04 : 1)
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                    Row { anchors.centerIn: parent; spacing: 6
                        Icon { name: w.running ? "pause" : "play_arrow"; size: 20; color: "#101218" }
                        Text { text: w.running ? "Pause" : (w.remaining === w.totalSec ? "Start" : "Resume"); color: "#101218"; font.family: Theme.font; font.weight: Font.DemiBold; font.pixelSize: 13 } }
                    MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.start() } }
                IconButton { width: 40; height: 40; radius: 20; icon: "restart_alt"; onClicked: w.reset() } }
        }
    }
}
