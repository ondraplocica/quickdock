import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"

// Wallpaper switcher: a thumbnail grid of the images in your wallpaper folder(s); click one to set it.
// widgetConfig.wallpaper = {
//   "dirs": ["~/Pictures/Wallpapers"],                 // folders searched (default ~/Pictures/Wallpapers and ~/Pictures)
//   "command": ["swww", "img", "{file}"]               // optional: your own setter, {file} is replaced by the image path
// }
// Without "command" the backend is detected: DankMaterialShell (dms), awww, swww or hyprpaper.
Tile {
    id: w
    implicitWidth: Theme.tileHeight
    readonly property string home: Quickshell.env("HOME")
    readonly property var dirs: Array.isArray(config.dirs) && config.dirs.length ? config.dirs : ["~/Pictures/Wallpapers", "~/Pictures"]
    property var files: []
    property string backend: "none"
    property string current: ""
    property bool loaded: false
    function toggle() { pop.open = !pop.open; }
    onClicked: toggle()

    function setCmd(file) {
        if (Array.isArray(config.command) && config.command.length) return config.command.map(a => String(a).split("{file}").join(file));
        switch (backend) {
        case "dms": return ["dms", "ipc", "call", "wallpaper", "set", file];
        case "awww": return ["awww", "img", file];
        case "swww": return ["swww", "img", file];
        case "hyprpaper": return ["sh", "-c", 'hyprctl hyprpaper preload "$1" && hyprctl hyprpaper wallpaper ",$1"', "sh", file];
        }
        return null;
    }
    readonly property bool canSet: (Array.isArray(config.command) && config.command.length > 0) || backend !== "none"
    function apply(file) {
        // only ever apply a file from our own listing
        if (!files.some(f => f.path === file)) return;
        const c = setCmd(file);
        if (!c) return;
        w.current = file;
        Quickshell.execDetached(c);
        reload.restart();
    }
    function random() { if (files.length) apply(files[Math.floor(Math.random() * files.length)].path); }
    function refresh() { if (!scan.running) scan.running = true; }

    Process {
        id: scan
        command: ["python3", "-I", String(Qt.resolvedUrl("wallpapers.py")).replace("file://", ""), JSON.stringify(w.dirs)]
        stdout: StdioCollector { onStreamFinished: {
            try { const r = JSON.parse(text); if (r.ok) { w.files = r.files; w.backend = r.backend; if (r.current) w.current = r.current; } } catch (e) {}
            w.loaded = true;
        } }
    }
    Timer { id: reload; interval: 1200; onTriggered: w.refresh() }
    Component.onCompleted: refresh()

    Icon { anchors.centerIn: parent; name: "wallpaper"; size: 24 }

    Popover {
        id: pop
        target: w
        panelWidth: 480
        panelHeight: 430
        onOpenChanged: if (open) w.refresh()
        Item {
            anchors.fill: parent
            Text { x: 18; y: 16; text: "Wallpaper"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
            Row { anchors.right: parent.right; anchors.rightMargin: 14; y: 10; spacing: 6
                Rectangle { height: 28; width: rl.implicitWidth + 22; radius: 14; opacity: w.canSet && w.files.length ? 1 : 0.4
                    color: rm.containsMouse ? Theme.tileFillHover : Qt.rgba(1, 1, 1, 0.08)
                    Row { id: rl; anchors.centerIn: parent; spacing: 5
                        Icon { name: "shuffle"; size: 15; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Random"; color: Theme.text; font.family: Theme.font; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter } }
                    MouseArea { id: rm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.random() } }
                Rectangle { height: 28; width: fl.implicitWidth + 22; radius: 14
                    color: fm.containsMouse ? Theme.tileFillHover : Qt.rgba(1, 1, 1, 0.08)
                    Text { id: fl; anchors.centerIn: parent; text: "Open folder"; color: Theme.text; font.family: Theme.font; font.pixelSize: 11 }
                    MouseArea { id: fm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { const d = String(w.dirs[0]); Quickshell.execDetached(["xdg-open", d.indexOf("~/") === 0 ? w.home + d.slice(1) : d]); } } }
            }
            Text { visible: w.loaded && w.files.length === 0; x: 18; y: 70; width: parent.width - 36; wrapMode: Text.WordWrap
                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12
                text: "No images found in " + w.dirs.join(", ") + ". Put some wallpapers there, or set widgetConfig.wallpaper.dirs." }
            Text { visible: w.loaded && w.files.length > 0 && !w.canSet; x: 18; y: 44; width: parent.width - 36; wrapMode: Text.WordWrap
                color: Theme.warn; font.family: Theme.font; font.pixelSize: 11
                text: "No wallpaper setter found (dms, awww, swww, hyprpaper). Set widgetConfig.wallpaper.command." }
            GridView {
                id: grid
                x: 12; y: 62; width: parent.width - 24; height: parent.height - 74
                clip: true; cellWidth: Math.floor(width / 3); cellHeight: 98
                boundsBehavior: Flickable.StopAtBounds
                model: w.files
                delegate: Item {
                    id: cell
                    required property var modelData
                    width: grid.cellWidth; height: grid.cellHeight
                    readonly property bool cur: w.current !== "" && w.current === modelData.path
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 4; radius: 12; clip: true
                        color: Theme.tileFill
                        border.width: cell.cur ? 2 : 1; border.color: cell.cur ? Theme.accent : (cm.containsMouse ? Theme.hairlineHover : Theme.hairline)
                        Image { anchors.fill: parent; anchors.margins: cell.cur ? 2 : 1; fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: false
                            sourceSize: Qt.size(300, 190); smooth: true; mipmap: true; source: "file://" + cell.modelData.path }
                        Rectangle { visible: cm.containsMouse; anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 20; color: Qt.rgba(0, 0, 0, 0.6)
                            Text { anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6; verticalAlignment: Text.AlignVCenter; elide: Text.ElideMiddle; textFormat: Text.PlainText
                                text: cell.modelData.name; color: "#fff"; font.family: Theme.font; font.pixelSize: 10 } }
                        Rectangle { visible: cell.cur; x: parent.width - 24; y: 6; width: 18; height: 18; radius: 9; color: Theme.accent
                            Icon { anchors.centerIn: parent; name: "check"; size: 13; color: "#101218" } }
                        MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: w.canSet ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: if (w.canSet) w.apply(cell.modelData.path) }
                    }
                }
            }
        }
    }
}
