import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"

Tile {
    id: w
    implicitWidth: Theme.tileHeight
    property var items: []
    property string query: ""
    function toggle() { if (!pop.open) { loader.running = true; q.text = ""; } pop.open = !pop.open; if (pop.open) q.forceActiveFocus(); }
    onClicked: toggle()
    function copy(id) { Quickshell.execDetached(["sh", "-c", "cliphist decode " + id + " | wl-copy"]); pop.open = false; }
    function del(id) { Quickshell.execDetached(["sh", "-c", "cliphist list | grep -m1 '^" + id + "\t' | cliphist delete"]); loader.running = true; }
    readonly property var shown: {
        const s = query.trim().toLowerCase();
        return (s ? items.filter(i => i.t.toLowerCase().indexOf(s) >= 0) : items).slice(0, 9);
    }

    Process {
        id: loader
        command: ["sh", "-c", "cliphist list | head -60"]
        stdout: StdioCollector {
            onStreamFinished: {
                w.items = text.split("\n").filter(l => l).map(l => {
                    const i = l.indexOf("\t");
                    const t = l.slice(i + 1);
                    return { id: l.slice(0, i), t: t, img: t.indexOf("[[ binary data") === 0 };
                });
            }
        }
    }

    Icon { anchors.centerIn: parent; name: "content_paste"; size: 24 }

    Popover {
        id: pop
        target: w
        panelWidth: 400
        panelHeight: 70 + Math.max(1, w.shown.length) * 44
        Column {
            anchors { fill: parent; margins: 12 }
            spacing: 4
            Rectangle {
                width: parent.width; height: 38; radius: 12; color: Theme.tileFill
                border.width: 1; border.color: q.activeFocus ? Theme.accent : Theme.hairline
                Behavior on border.color { ColorAnimation { duration: 150 } }
                Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 18; color: Theme.textDim }
                TextInput { id: q
                    anchors { left: parent.left; leftMargin: 36; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13; clip: true
                    onTextChanged: w.query = text
                    onAccepted: if (w.shown[0]) w.copy(w.shown[0].id)
                    Text { visible: !q.text; text: "Search clipboard history"; color: Theme.textDim; font: q.font; anchors.verticalCenter: parent.verticalCenter } }
            }
            Text { visible: w.shown.length === 0; text: "Nothing copied yet"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13; topPadding: 8 }
            Repeater {
                model: pop.open ? w.shown : []
                delegate: Rectangle {
                    id: crow
                    required property var modelData
                    required property int index
                    width: parent.width; height: 40; radius: 10
                    color: cm.containsMouse ? Theme.tileFillHover : "transparent"
                    opacity: 0
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Component.onCompleted: fadeIn.start()
                    SequentialAnimation { id: fadeIn
                        PauseAnimation { duration: index * 25 }
                        NumberAnimation { target: crow; property: "opacity"; to: 1; duration: 180 } }
                    Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: modelData.img ? "image" : "notes"; size: 18; color: Theme.accent }
                    Text { textFormat: Text.PlainText; anchors { left: parent.left; leftMargin: 38; right: dbtn.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        elide: Text.ElideRight; maximumLineCount: 1; text: modelData.t.replace(/\s+/g, " ")
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                    MouseArea { id: cm; anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: dbtn.left }
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.copy(modelData.id) }
                    IconButton { id: dbtn; width: 28; height: 28; radius: 14; icon: "close"; opacity: cm.containsMouse || containsMouse ? 1 : 0
                        readonly property bool containsMouse: false
                        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        onClicked: w.del(modelData.id) }
                }
            }
        }
    }
}
