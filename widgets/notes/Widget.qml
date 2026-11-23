import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"

Tile {
    id: w
    implicitWidth: Theme.tileHeight
    readonly property string file: config.file ?? (Quickshell.env("HOME") + "/.local/share/quickdock/notes.md")
    property bool loaded: false
    property bool dirty: false
    function toggle() { pop.open = !pop.open; if (pop.open) area.forceActiveFocus(); }
    onClicked: toggle()

    Process { id: mk; command: ["mkdir", "-p", w.file.slice(0, w.file.lastIndexOf("/"))]; running: true }
    FileView {
        id: fv
        path: w.file
        printErrors: false
        onLoaded: { area.text = text(); w.loaded = true; w.dirty = false; }
        onLoadFailed: w.loaded = true      // first run: file doesn't exist yet
    }
    Timer { id: save; interval: 700; onTriggered: { if (w.loaded) { fv.setText(area.text); w.dirty = false; } } }
    Component.onDestruction: if (w.dirty) fv.setText(area.text)

    Icon { anchors.centerIn: parent; name: "sticky_note_2"; size: 24 }
    Rectangle { width: 7; height: 7; radius: 4; color: Theme.accent
        anchors { right: parent.right; top: parent.top; margins: 9 }
        visible: area.length > 0 }

    Popover {
        id: pop
        target: w
        panelWidth: 380
        panelHeight: 360
        Column {
            anchors { fill: parent; margins: 14 }
            spacing: 8
            Row { width: parent.width
                Text { text: "Notes"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold; width: parent.width / 2 }
                Text { text: w.dirty ? "Saving…" : (area.length + " chars · saved"); color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11
                    width: parent.width / 2; horizontalAlignment: Text.AlignRight } }
            Rectangle {
                width: parent.width; height: parent.height - 34; radius: 12; color: Theme.tileFill
                border.width: 1; border.color: area.activeFocus ? Theme.accent : Theme.hairline
                Behavior on border.color { ColorAnimation { duration: 150 } }
                Flickable {
                    id: fl
                    anchors { fill: parent; margins: 10 }
                    contentWidth: width; contentHeight: area.contentHeight; clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    TextEdit {
                        id: area
                        width: fl.width
                        color: Theme.text; selectionColor: Theme.accent; selectedTextColor: "#101218"
                        font.family: Theme.font; font.pixelSize: 13
                        wrapMode: TextEdit.Wrap
                        onTextChanged: if (w.loaded) { w.dirty = true; save.restart(); }
                        onCursorRectangleChanged: {
                            if (cursorRectangle.y < fl.contentY) fl.contentY = cursorRectangle.y;
                            else if (cursorRectangle.y + cursorRectangle.height > fl.contentY + fl.height) fl.contentY = cursorRectangle.y + cursorRectangle.height - fl.height;
                        }
                    }
                }
            }
        }
    }
}
