import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"

// A "stack": pinned apps, files and folders. Items live in dock.json -> widgetConfig[<instance>].items
//   [{ "type": "app", "id": "org.gnome.Nautilus" }, { "type": "file", "path": "/home/me/doc.pdf" }, { "type": "folder", "path": "/home/me/Projects" }]
Tile {
    id: w
    implicitWidth: Theme.tileHeight
    readonly property string key: instanceId || "folder"
    readonly property var cfgBlock: (Dock.cfg.widgetConfig || {})[key] || ({})
    readonly property var items: cfgBlock.items || []
    readonly property string title: cfgBlock.name || "Pinned"
    property bool addingApp: false
    property string query: ""
    function toggle() { pop.open = !pop.open; if (!pop.open) addingApp = false; }
    onClicked: toggle()
    Connections { target: Dock; function onCloseAll() { w.addingApp = false; } }

    function save(list) { Dock.saveWidget(key, { items: list, name: title }); }
    function addItem(it) {
        if (items.some(x => x.type === it.type && x.id === it.id && x.path === it.path)) return;
        save(items.concat([it]));
    }
    function removeAt(i) { const a = items.slice(); a.splice(i, 1); save(a); }
    function base(p) { return p.replace(/\/+$/, "").split("/").pop(); }
    property int entriesRev: 0           // bumped when the desktop-entry list (re)loads, so lookups re-evaluate
    Connections { target: DesktopEntries.applications; function onValuesChanged() { w.entriesRev++; } }
    function entryOf(it) { const _ = entriesRev; return it.type === "app" ? DesktopEntries.byId(it.id) : null; }
    function glyph(it) {
        if (it.type === "folder") return "folder";
        const n = (it.path || "").toLowerCase();
        if (/\.(stl|3mf|obj|step|stp)$/.test(n)) return "view_in_ar";
        if (/\.(png|jpe?g|gif|webp|svg)$/.test(n)) return "image";
        if (/\.(mp4|mkv|webm|mov)$/.test(n)) return "movie";
        if (/\.(mp3|flac|ogg|wav)$/.test(n)) return "music_note";
        if (/\.pdf$/.test(n)) return "picture_as_pdf";
        if (/\.(zip|tar|gz|7z|xz)$/.test(n)) return "folder_zip";
        if (/\.(py|js|ts|qml|sh|json|md|txt)$/.test(n)) return "code";
        return "draft";
    }
    function open(it) {
        pop.open = false;
        if (it.type === "app") { const e = entryOf(it); if (e) e.execute(); }
        else Quickshell.execDetached(["xdg-open", it.path]);
    }
    function pick(kind) {
        pop.open = false;
        picker.kind = kind;
        picker.command = kind === "folder" ? ["zenity", "--file-selection", "--directory", "--title=Pin a folder"]
                                           : ["zenity", "--file-selection", "--title=Pin a file"];
        picker.running = true;
    }
    Process { id: picker; property string kind: "file"
        stdout: StdioCollector { onStreamFinished: { const p = text.trim(); if (p) w.addItem({ type: picker.kind, path: p }); } } }

    // ---- tile: 2x2 mini stack of the first four items ----
    Grid {
        anchors.centerIn: parent
        columns: 2; spacing: 3
        visible: w.items.length > 0
        Repeater {
            model: w.items.slice(0, 4)
            delegate: Item {
                required property var modelData
                width: 16; height: 16
                Image { id: mi; anchors.fill: parent; sourceSize: Qt.size(48, 48); smooth: true; mipmap: true
                    source: { const e = w.entryOf(modelData); return e ? Quickshell.iconPath(e.icon, true) : ""; }
                    visible: status === Image.Ready }
                Icon { anchors.centerIn: parent; visible: mi.status !== Image.Ready; size: 15
                    name: modelData.type === "app" ? "apps" : w.glyph(modelData); color: Theme.accent }
            }
        }
    }
    Icon { anchors.centerIn: parent; visible: w.items.length === 0; name: "folder_special"; size: 24 }

    // ---- dropdown ----
    Popover {
        id: pop
        target: w
        panelWidth: 372
        readonly property int rows: Math.max(1, Math.ceil((w.items.length + 1) / 4))
        panelHeight: w.addingApp ? 400 : 118 + rows * 92
        Column {
            anchors { fill: parent; margins: 16 }
            spacing: 12
            Row { width: parent.width; height: 28
                Text { textFormat: Text.PlainText; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 28; text: w.title
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Bold }
                Text { anchors.verticalCenter: parent.verticalCenter; text: w.items.length; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 } }

            Grid {   // items
                visible: !w.addingApp
                columns: 4; spacing: 6; width: parent.width
                readonly property real cw: (width - 3 * spacing) / 4
                Repeater {
                    model: w.items
                    delegate: Rectangle {
                        id: cellR
                        required property var modelData
                        required property int index
                        width: parent.cw; height: 86; radius: 14
                        color: cm.containsMouse ? Theme.tileFillHover : Qt.rgba(1, 1, 1, 0.04)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        scale: cm.pressed ? 0.95 : 1
                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }
                        Image { id: ci; x: (parent.width - 40) / 2; y: 10; width: 40; height: 40; sourceSize: Qt.size(96, 96); smooth: true; mipmap: true
                            source: { const e = w.entryOf(cellR.modelData); return e ? Quickshell.iconPath(e.icon, true) : ""; }
                            visible: status === Image.Ready }
                        Icon { x: (parent.width - 40) / 2 + 4; y: 14; visible: ci.status !== Image.Ready; size: 32; color: Theme.accent
                            name: cellR.modelData.type === "app" ? "apps" : w.glyph(cellR.modelData) }
                        Text { x: 4; y: 56; width: parent.width - 8; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideMiddle; maximumLineCount: 2; wrapMode: Text.WrapAnywhere
                            text: { const e = w.entryOf(cellR.modelData); return e ? e.name : w.base(cellR.modelData.path || cellR.modelData.id || ""); }
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 11 }
                        MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.open(cellR.modelData) }
                        Rectangle {   // remove button on hover
                            visible: cm.containsMouse || rm.containsMouse
                            width: 20; height: 20; radius: 10; x: parent.width - 24; y: 4; color: Theme.popFill; border.width: 1; border.color: Theme.hairlineHover
                            Icon { anchors.centerIn: parent; name: "close"; size: 13; color: Theme.textDim }
                            MouseArea { id: rm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.removeAt(cellR.index) }
                        }
                    }
                }
                Rectangle {   // + add
                    width: parent.cw; height: 86; radius: 14; color: Qt.rgba(1, 1, 1, 0.03)
                    border.width: 1; border.color: Theme.hairlineHover
                    Icon { anchors.centerIn: parent; name: "add"; size: 26; color: Theme.textDim }
                }
            }
            Row {   // add actions
                visible: !w.addingApp; spacing: 8
                Repeater {
                    model: [ { l: "Add app", i: "apps", a: "app" }, { l: "Add file", i: "draft", a: "file" }, { l: "Add folder", i: "folder", a: "folder" } ]
                    delegate: Rectangle { required property var modelData
                        height: 34; width: al.implicitWidth + 44; radius: 17; color: am.containsMouse ? Theme.tileFillHover : Qt.rgba(1, 1, 1, 0.07)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Row { anchors.centerIn: parent; spacing: 6
                            Icon { name: modelData.i; size: 16; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                            Text { id: al; text: modelData.l; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter } }
                        MouseArea { id: am; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { if (modelData.a === "app") { w.addingApp = true; w.query = ""; sf.text = ""; sf.forceActiveFocus(); } else w.pick(modelData.a); } } }
                }
            }

            // ---- app picker (inline) ----
            Rectangle {
                visible: w.addingApp
                width: parent.width; height: 38; radius: 12; color: Theme.tileFill
                border.width: 1; border.color: sf.activeFocus ? Theme.accent : Theme.hairline
                Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 18; color: Theme.textDim }
                TextInput { id: sf
                    anchors { left: parent.left; leftMargin: 36; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13; clip: true
                    onTextChanged: w.query = text
                    Text { visible: !sf.text; text: "Search apps to pin"; color: Theme.textDim; font: sf.font; anchors.verticalCenter: parent.verticalCenter } }
            }
            Repeater {
                model: w.addingApp ? DesktopEntries.applications.values.filter(e => !e.noDisplay && (!w.query || e.name.toLowerCase().indexOf(w.query.toLowerCase()) >= 0)).sort((a, b) => a.name.localeCompare(b.name)).slice(0, 6) : []
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width; height: 40; radius: 10; color: rma.containsMouse ? Theme.tileFillHover : "transparent"
                    Image { id: ri; x: 8; anchors.verticalCenter: parent.verticalCenter; width: 26; height: 26; sourceSize: Qt.size(52, 52); smooth: true; mipmap: true
                        source: Quickshell.iconPath(modelData.icon, true); visible: status === Image.Ready }
                    Text { x: 44; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 60; elide: Text.ElideRight; text: modelData.name
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                    MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { w.addItem({ type: "app", id: modelData.id }); w.addingApp = false; } }
                }
            }
            Rectangle { visible: w.addingApp; height: 30; width: 90; radius: 15; color: Qt.rgba(1, 1, 1, 0.07)
                Text { anchors.centerIn: parent; text: "Back"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: w.addingApp = false } }
        }
    }
}
