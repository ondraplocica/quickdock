import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"

Tile {
    id: w
    implicitWidth: Theme.tileHeight
    property string lastShot: ""
    readonly property string dir: config.dir ?? "~/Pictures/Screenshots"
    // Optional config.command is called as `<command> region|window|full`;
    // default copies to the clipboard with grim.
    readonly property string cmd: config.command ?? ""
    function toggle() { if (!pop.open) refresh(); pop.open = !pop.open; }
    onClicked: toggle()
    function refresh() { last.running = true; }
    function shoot(mode) {
        pop.open = false;
        let c;
        if (cmd) c = cmd + " " + mode;
        else if (mode === "region") c = 'grim -g "$(slurp)" - | wl-copy';
        else if (mode === "window") c = 'grim -g "$(hyprctl activewindow -j | jq -r \'"\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])"\')" - | wl-copy';
        else c = "grim - | wl-copy";
        Quickshell.execDetached(["sh", "-c", "sleep 0.45; " + c]);
    }
    Process { id: last; command: ["sh", "-c", "ls -t " + w.dir.replace("~", "$HOME") + "/* 2>/dev/null | head -1"]
        stdout: StdioCollector { onStreamFinished: w.lastShot = text.trim() } }

    Icon { anchors.centerIn: parent; name: "screenshot_region"; size: 24 }

    Popover {
        id: pop
        target: w
        panelWidth: 300
        panelHeight: w.lastShot ? 250 : 120
        Column {
            anchors { fill: parent; margins: 14 }
            spacing: 12
            Row {
                spacing: 8; anchors.horizontalCenter: parent.horizontalCenter
                Repeater {
                    model: [ { l: "Region", i: "crop", m: "region" }, { l: "Window", i: "web_asset", m: "window" }, { l: "Screen", i: "desktop_windows", m: "full" } ]
                    delegate: Rectangle {
                        required property var modelData
                        width: 84; height: 76; radius: 14; color: Theme.tileFill
                        scale: ma.pressed ? 0.93 : (ma.containsMouse ? 1.05 : 1)
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                        Column { anchors.centerIn: parent; spacing: 6
                            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: modelData.i; size: 26; color: Theme.accent }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.l; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 } }
                        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.shoot(modelData.m) }
                    }
                }
            }
            Rectangle {
                visible: w.lastShot !== ""
                width: parent.width; height: 120; radius: 12; clip: true; color: Theme.tileFill
                Image { anchors.fill: parent; source: w.lastShot ? "file://" + w.lastShot : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true
                    opacity: status === Image.Ready ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 300 } } }
                Text { anchors { left: parent.left; bottom: parent.bottom; margins: 8 } text: "Last screenshot, click to open"
                    color: "white"; font.family: Theme.font; font.pixelSize: 11; style: Text.Outline; styleColor: "#99000000" }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["xdg-open", w.lastShot]) }
            }
        }
    }
}
