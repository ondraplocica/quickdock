import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"

Tile {
    id: w
    implicitWidth: Theme.tileHeight
    property var files: []
    function toggle() { if (!pop.open) loader.running = true; pop.open = !pop.open; }
    onClicked: toggle()

    function iconFor(mime, name) {
        mime = mime || ""; name = (name || "").toLowerCase();
        if (/\.(stl|3mf|obj|step|stp)$/.test(name)) return "view_in_ar";
        if (mime.indexOf("image/") === 0) return "image";
        if (mime.indexOf("video/") === 0) return "movie";
        if (mime.indexOf("audio/") === 0) return "music_note";
        if (mime.indexOf("pdf") >= 0) return "picture_as_pdf";
        if (mime.indexOf("zip") >= 0 || mime.indexOf("tar") >= 0) return "folder_zip";
        return "description";
    }
    function ago(iso) {
        const s = (Date.now() - new Date(iso).getTime()) / 1000;
        if (s < 3600) return Math.max(1, Math.round(s / 60)) + " min ago";
        if (s < 86400) return Math.round(s / 3600) + " h ago";
        return Math.round(s / 86400) + " d ago";
    }
    Process {
        id: loader
        command: ["python3", "-I", "-c", `
import json,os,urllib.parse,xml.etree.ElementTree as ET
p=os.path.expanduser('~/.local/share/recently-used.xbel'); out=[]
try:
    for b in ET.parse(p).getroot().iter('bookmark'):
        u=urllib.parse.unquote(b.get('href','')).replace('file://','')
        if not os.path.exists(u): continue
        m=''
        for e in b.iter():
            if e.tag.endswith('mime-type'): m=e.get('type','')
        out.append({'path':u,'name':os.path.basename(u),'dir':os.path.dirname(u).replace(os.path.expanduser('~'),'~'),'mime':m,'t':b.get('visited') or b.get('modified') or ''})
except Exception: pass
out.sort(key=lambda x:x['t'],reverse=True); print(json.dumps(out[:10]))`]
        stdout: StdioCollector { onStreamFinished: { try { w.files = JSON.parse(text); } catch (e) { w.files = []; } } }
    }

    Icon { anchors.centerIn: parent; name: "history"; size: 24 }

    Popover {
        id: pop
        target: w
        panelWidth: 380
        panelHeight: 60 + Math.max(1, w.files.length) * 48
        Column {
            anchors { fill: parent; margins: 14 }
            spacing: 2
            Text { text: "Recent files"; color: Theme.text; font.family: Theme.font; font.weight: Font.DemiBold; font.pixelSize: 13; bottomPadding: 6 }
            Text { visible: w.files.length === 0; text: "Nothing yet"; color: Theme.textDim; font.family: Theme.font }
            Repeater {
                model: pop.open ? w.files : []
                delegate: Rectangle {
                    id: rrow
                    required property var modelData
                    required property int index
                    width: parent.width; height: 46; radius: 10
                    color: ma.containsMouse ? Theme.tileFillHover : "transparent"
                    opacity: 0; x: 12
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Component.onCompleted: ap.start()
                    SequentialAnimation { id: ap
                        PauseAnimation { duration: index * 30 }
                        ParallelAnimation {
                            NumberAnimation { target: rrow; property: "opacity"; to: 1; duration: 200 }
                            NumberAnimation { target: rrow; property: "x"; to: 0; duration: 260; easing.type: Easing.OutCubic } } }
                    Row { anchors { fill: parent; leftMargin: 10 } spacing: 12
                        Icon { anchors.verticalCenter: parent.verticalCenter; name: w.iconFor(modelData.mime, modelData.name); size: 22; color: Theme.accent }
                        Column { anchors.verticalCenter: parent.verticalCenter; width: 280
                            Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideMiddle; text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                            Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideMiddle; text: modelData.dir + " · " + w.ago(modelData.t)
                                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 } }
                    }
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { Quickshell.execDetached(["xdg-open", modelData.path]); pop.open = false; } }
                }
            }
        }
    }
}
