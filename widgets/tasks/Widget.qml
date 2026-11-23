import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"

Tile {
    id: w
    implicitWidth: row.implicitWidth + 24
    readonly property string script: String(Qt.resolvedUrl("tasks.py")).replace("file://", "")
    property var tasks: []
    property string state: "loading"        // loading | ok | auth | no-client | error
    readonly property int count: tasks.length
    active: false
    function toggle() { if (!pop.open) refresh(); pop.open = !pop.open; }
    onClicked: toggle()
    function refresh() { lister.running = true; }
    function act(args) { actor.command = ["python3", "-I", script].concat(args); actor.running = true; }

    Timer { interval: 300000; running: true; repeat: true; triggeredOnStart: true; onTriggered: w.refresh() }
    Process {
        id: lister
        command: ["python3", "-I", w.script, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    if (r.ok) { w.tasks = r.tasks; w.state = "ok"; }
                    else w.state = (r.error === "auth" || r.error === "no-client") ? r.error : "error";
                } catch (e) { w.state = "error"; }
            }
        }
    }
    Process { id: actor; stdout: StdioCollector { onStreamFinished: w.refresh() } }
    Process { id: authp; command: ["python3", "-I", w.script, "auth"]
        stdout: StdioCollector { onStreamFinished: w.refresh() } }

    Row {
        id: row
        anchors.centerIn: parent; spacing: 8
        Icon { anchors.verticalCenter: parent.verticalCenter; name: "checklist"; size: 24
            color: w.state === "ok" ? Theme.text : Theme.textDim }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: w.state === "ok"
            text: w.count
            color: w.count > 0 ? Theme.accent : Theme.textDim
            font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Bold
        }
    }

    Popover {
        id: pop
        target: w
        panelWidth: 340
        panelHeight: w.state === "ok" ? Math.min(520, 120 + Math.max(1, w.count) * 42) : 190
        onOpenChanged: if (open && w.state === "ok") field.forceActiveFocus()

        Column {   // setup / error states
            visible: w.state !== "ok"
            anchors { fill: parent; margins: 18 }
            spacing: 12
            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "checklist"; size: 36; color: Theme.accent }
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                text: w.state === "no-client" ? "Add your Google OAuth client first (see widgets/tasks/README.md)."
                    : w.state === "auth" ? "Connect your Google account to see your tasks."
                    : w.state === "loading" ? "Loading…" : "Couldn't reach Google Tasks." }
            Rectangle {
                visible: w.state === "auth" || w.state === "error"
                anchors.horizontalCenter: parent.horizontalCenter
                width: 190; height: 38; radius: 19; color: Theme.accent
                scale: bm.pressed ? 0.94 : (bm.containsMouse ? 1.04 : 1)
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                Text { anchors.centerIn: parent; text: w.state === "auth" ? "Connect Google account" : "Retry"
                    color: "#101218"; font.family: Theme.font; font.weight: Font.DemiBold; font.pixelSize: 13 }
                MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { if (w.state === "auth") authp.running = true; else w.refresh(); } }
            }
        }

        Column {   // task list
            visible: w.state === "ok"
            anchors { fill: parent; margins: 14 }
            spacing: 6
            Text { text: "Tasks"; color: Theme.text; font.family: Theme.font; font.weight: Font.DemiBold; font.pixelSize: 13 }
            Rectangle {   // add field
                width: parent.width; height: 38; radius: 12; color: Theme.tileFill
                border.width: 1; border.color: field.activeFocus ? Theme.accent : Theme.hairline
                Behavior on border.color { ColorAnimation { duration: 150 } }
                Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "add"; size: 18; color: Theme.textDim }
                TextInput {
                    id: field
                    anchors { left: parent.left; leftMargin: 36; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13; clip: true
                    onAccepted: { if (text.trim()) { w.act(["add", text.trim()]); text = ""; } }
                    Text { visible: !field.text && !field.activeFocus; text: "Add a task"; color: Theme.textDim
                        font: field.font; anchors.verticalCenter: parent.verticalCenter }
                }
            }
            Text { visible: w.count === 0; text: "All done 🎉"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13; topPadding: 8 }
            Repeater {
                model: w.tasks
                delegate: Rectangle {
                    id: trow
                    required property var modelData
                    required property int index
                    property bool checked: false
                    width: parent.width; height: 38; radius: 10
                    color: tma.containsMouse ? Theme.tileFillHover : "transparent"
                    opacity: checked ? 0.4 : 1
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Rectangle {   // checkbox
                        id: cb
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        width: 20; height: 20; radius: 10
                        color: trow.checked ? Theme.accent : "transparent"
                        border.width: 2; border.color: trow.checked ? Theme.accent : Theme.textDim
                        Behavior on color { ColorAnimation { duration: 160 } }
                        Icon { anchors.centerIn: parent; name: "check"; size: 14; color: "#101218"
                            scale: trow.checked ? 1 : 0; Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } } }
                    }
                    Column {
                        anchors { left: cb.right; leftMargin: 10; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: modelData.title
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.strikeout: trow.checked }
                        Text { visible: modelData.due !== ""; text: "Due " + modelData.due
                            color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10 }
                    }
                    MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { trow.checked = true; w.act(["done", modelData.id]); } }
                }
            }
        }
    }
}
