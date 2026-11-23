import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"

// Controls DND through DankMaterialShell's notification daemon (`dms ipc`).
Tile {
    id: w
    implicitWidth: Theme.tileHeight
    property bool on: false
    active: on
    function toggle() { pop.open = !pop.open; }
    function run(args) { Quickshell.execDetached(["dms", "ipc", "call", "notifications"].concat(args)); poll.restart(); chk.running = true; }
    onClicked: run(["toggleDoNotDisturb"])

    Timer { id: poll; interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: chk.running = true }
    Process { id: chk; command: ["dms", "ipc", "call", "notifications", "getDoNotDisturb"]
        stdout: StdioCollector { onStreamFinished: w.on = text.trim() === "true" } }

    TapHandler { acceptedButtons: Qt.RightButton; onTapped: pop.open = !pop.open }

    Icon {
        id: moon
        anchors.centerIn: parent
        name: "bedtime"                       // crescent moon; accent-coloured while Do Not Disturb is on
        size: 24
        color: w.on ? Theme.accent : Theme.text
        Behavior on color { ColorAnimation { duration: 220 } }
        SequentialAnimation {                 // little pop + tilt whenever it flips
            id: swing
            ParallelAnimation {
                NumberAnimation { target: moon; property: "scale"; to: 1.28; duration: 110; easing.type: Easing.OutQuad }
                NumberAnimation { target: moon; property: "rotation"; to: -18; duration: 110 }
            }
            ParallelAnimation {
                NumberAnimation { target: moon; property: "scale"; to: 1; duration: 220; easing.type: Easing.OutBack }
                NumberAnimation { target: moon; property: "rotation"; to: 0; duration: 220; easing.type: Easing.OutBack }
            }
        }
    }
    onOnChanged: swing.restart()

    Popover {
        id: pop
        target: w
        panelWidth: 230
        panelHeight: 252
        Column {
            anchors { fill: parent; margins: 12 }
            spacing: 4
            Text { text: w.on ? "Do Not Disturb is on" : "Do Not Disturb"; color: Theme.text
                font.family: Theme.font; font.weight: Font.DemiBold; font.pixelSize: 13; bottomPadding: 6 }
            Repeater {
                model: [ { l: "For 30 minutes", a: ["enableDoNotDisturbFor", "30"] }, { l: "For 1 hour", a: ["enableDoNotDisturbFor", "60"] },
                         { l: "For 2 hours", a: ["enableDoNotDisturbFor", "120"] }, { l: "Until I turn it off", a: ["enableDoNotDisturbIndefinitely"] },
                         { l: "Turn off", a: ["disableDoNotDisturb"], bad: true } ]
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width; height: 36; radius: 10
                    color: ma.containsMouse ? Theme.tileFillHover : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        text: modelData.l; color: modelData.bad ? Theme.bad : Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { w.run(modelData.a); pop.open = false; } }
                }
            }
        }
    }
}
