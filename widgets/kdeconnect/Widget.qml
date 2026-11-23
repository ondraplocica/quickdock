import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import "../../core"

Tile {
    id: w
    implicitWidth: row.implicitWidth + 24
    readonly property string dev: config.device ?? ""
    property int battery: -1
    property bool reachable: false
    property bool charging: false
    property string devName: "Phone"
    function toggle() { pop.open = !pop.open; }
    onClicked: toggle()
    // Resolved device: the configured id if it is reachable, else the first reachable paired phone
    // (else any reachable paired device), else the configured id. Survives re-pairing / new device ids.
    property string cur: dev
    readonly property string base: "/modules/kdeconnect/devices/" + cur
    readonly property string pollScript: [
        'S="busctl --user get-property org.kde.kdeconnect"',
        'L=$(busctl --user call org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon devices bb true true 2>/dev/null | grep -o "\\"[0-9a-f]\\{32\\}\\"" | tr -d \'"\')',
        'D=""; for i in $L; do [ "$i" = "$1" ] && D=$i; done',
        'if [ -z "$D" ]; then for i in $L; do case "$($S /modules/kdeconnect/devices/$i org.kde.kdeconnect.device type 2>/dev/null)" in *phone*) D=$i; break;; esac; done; fi',
        '[ -z "$D" ] && D=$(echo "$L" | head -n1)',
        '[ -z "$D" ] && D=$1',
        'B=/modules/kdeconnect/devices/$D',
        'echo "$D"',
        '$S $B org.kde.kdeconnect.device isReachable 2>/dev/null',
        '$S $B/battery org.kde.kdeconnect.device.battery charge 2>/dev/null',
        '$S $B/battery org.kde.kdeconnect.device.battery isCharging 2>/dev/null',
        '$S $B org.kde.kdeconnect.device name 2>/dev/null'
    ].join("\n")
    Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: poll.running = true }
    Process {
        id: poll
        command: ["sh", "-c", w.pollScript, "sh", w.dev]
        stdout: StdioCollector { onStreamFinished: {
            const l = text.trim().split("\n");
            if (l[0]) w.cur = l[0];
            w.reachable = (l[1] || "").indexOf("true") >= 0;
            w.battery = parseInt((l[2] || "").replace(/[^0-9-]/g, "")); if (isNaN(w.battery)) w.battery = -1;
            w.charging = (l[3] || "").indexOf("true") >= 0;
            const n = (l[4] || "").match(/"(.*)"/); if (n) w.devName = n[1];
        } } }
    function act(flag) { Quickshell.execDetached(["kdeconnect-cli", "-d", cur, flag]); }

    // ---------- files from the phone ----------
    // widgetConfig.kdeconnect.folder (default ~/Phone) is where the phone's files should land. "Receive here" points
    // KDE Connect's share plugin at it (set-receive-folder.py); the dropdown then lists the newest files in it.
    readonly property string home: Quickshell.env("HOME")
    readonly property string folder: { const f = String(config.folder ?? "~/Phone").replace(/\/+$/, ""); return f.indexOf("~/") === 0 ? home + f.slice(1) : f; }
    property string incoming: ""                                  // what KDE Connect currently uses for this device
    readonly property bool receiving: incoming !== "" && incoming.replace(/\/+$/, "") === folder
    property int seen: -1                                         // file count when the dropdown was last open
    readonly property int fresh: (seen >= 0 && files.count > seen) ? files.count - seen : 0
    property bool busy: false
    property string err: ""
    function pretty(p) { return p.indexOf(home) === 0 ? "~" + p.slice(home.length) : p; }
    function size(b) { return b >= 1073741824 ? (b / 1073741824).toFixed(1) + " GB" : (b >= 1048576 ? (b / 1048576).toFixed(1) + " MB" : (b >= 1024 ? Math.round(b / 1024) + " kB" : b + " B")); }
    function ago(d) { const s = Math.max(0, Math.floor((Date.now() - d.getTime()) / 1000)); return s < 60 ? "now" : (s < 3600 ? Math.floor(s / 60) + " min ago" : (s < 86400 ? Math.floor(s / 3600) + " h ago" : Math.floor(s / 86400) + " d ago")); }
    function isImage(n) { return /\.(png|jpe?g|gif|webp|bmp)$/i.test(n); }
    function iconFor(n) {
        if (/\.(mp4|mkv|webm|mov|avi)$/i.test(n)) return "movie";
        if (/\.(mp3|ogg|flac|wav|m4a|opus)$/i.test(n)) return "music_note";
        if (/\.(pdf)$/i.test(n)) return "picture_as_pdf";
        if (/\.(zip|tar|gz|xz|7z|rar)$/i.test(n)) return "folder_zip";
        if (/\.(apk)$/i.test(n)) return "android";
        return "draft";
    }
    function openFolder() { Quickshell.execDetached(["xdg-open", folder]); }

    FolderListModel {
        id: files
        folder: "file://" + w.folder
        showDirs: false
        showDotAndDotDot: false
        showHidden: false
        sortField: FolderListModel.Time
        sortReversed: false             // Qt sorts by time newest-first already
        onStatusChanged: if (status === FolderListModel.Ready && w.seen < 0) w.seen = count
    }
    FileView {                          // KDE Connect's current receive folder for this device
        id: shareCfg
        path: w.home + "/.config/kdeconnect/" + w.cur + "/kdeconnect_share/config"
        printErrors: false              // does not exist until "Receive here" is used
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { const m = text().match(/^incoming_path=(.*)$/m); w.incoming = m ? m[1].trim() : ""; }
        onLoadFailed: w.incoming = ""
    }
    Process {
        id: setup
        command: ["python3", "-I", String(Qt.resolvedUrl("set-receive-folder.py")).replace("file://", ""), w.cur, w.folder]
        stdout: StdioCollector { onStreamFinished: { w.busy = false; w.err = text.trim() === "ok" ? "" : "Could not change the folder"; shareCfg.reload(); } }
        onExited: busy = false
    }
    Process {                           // pick a file on this PC and send it to the phone
        id: picker
        command: ["zenity", "--file-selection", "--multiple", "--separator=\n", "--title=Send to phone"]
        stdout: StdioCollector { onStreamFinished: text.trim().split("\n").filter(f => f.length > 0 && f[0] === "/").forEach(f => Quickshell.execDetached(["kdeconnect-cli", "-d", w.cur, "--share", f])) }
    }

    readonly property color batColor: w.battery <= 15 && !w.charging ? Theme.bad : Theme.good
    Row { id: row; anchors.centerIn: parent; spacing: 8
        // Unreachable / no battery data: plain icon
        Icon { visible: !w.reachable || w.battery < 0; anchors.verticalCenter: parent.verticalCenter
            name: w.reachable ? "smartphone" : "phonelink_off"; size: 24; color: w.reachable ? Theme.text : Theme.textDim }
        // Battery ring with the level (and a bolt while charging) inside
        Item { visible: w.reachable && w.battery >= 0; width: 34; height: 34; anchors.verticalCenter: parent.verticalCenter
            Ring { anchors.centerIn: parent; size: 34; thickness: 3.5; value: Math.max(0, w.battery) / 100; fill: w.batColor; endDot: true }
            Row { anchors.centerIn: parent; spacing: 0
                Icon { visible: w.charging; anchors.verticalCenter: parent.verticalCenter; name: "bolt"; size: 11; color: Theme.text }
                Text { anchors.verticalCenter: parent.verticalCenter; text: w.battery
                    color: Theme.text; font.family: Theme.font; font.pixelSize: w.battery >= 100 ? 10 : 12; font.weight: Font.Bold } } } }

    Rectangle {   // new files from the phone since the dropdown was last open
        visible: w.fresh > 0 && !pop.open
        x: parent.width - 14; y: 4; width: 10; height: 10; radius: 5; color: Theme.accent
    }

    Popover {
        id: pop
        target: w
        panelWidth: 340
        panelHeight: 214 + (w.receiving ? 0 : 66) + 30 + (files.count === 0 ? 46 : Math.min(files.count, 5) * 54)
        onOpenChanged: if (open) w.seen = files.count
        Column { anchors { fill: parent; margins: 16 } spacing: 12
            Row { spacing: 12
                Item { width: 58; height: 58; anchors.verticalCenter: parent.verticalCenter
                    Ring { anchors.centerIn: parent; size: 58; thickness: 6; value: Math.max(0, w.battery) / 100; fill: w.batColor; endDot: true }
                    Row { anchors.centerIn: parent; spacing: 0
                        Icon { visible: w.charging; anchors.verticalCenter: parent.verticalCenter; name: "bolt"; size: 16; color: Theme.text }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: w.battery >= 0 ? w.battery : "–"
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold } } }
                Column { anchors.verticalCenter: parent.verticalCenter
                    Text { textFormat: Text.PlainText; text: w.devName; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
                    Text { text: !w.reachable ? "Not reachable" : (w.battery >= 0 ? w.battery + "%" + (w.charging ? " · charging" : "") : "Connected")
                        color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 } } }
            Row { spacing: 8
                Repeater { model: [ { l: "Ring", i: "notifications_active", f: "--ring" }, { l: "Ping", i: "wifi_tethering", f: "--ping" }, { l: "Clipboard", i: "content_paste", f: "--send-clipboard" }, { l: "Send file", i: "upload_file", f: "pick" } ]
                    delegate: Rectangle { required property var modelData
                        width: 70; height: 60; radius: 14; color: Theme.tileFill; opacity: w.reachable ? 1 : 0.4
                        scale: bm.pressed ? 0.94 : (bm.containsMouse ? 1.05 : 1)
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                        Column { anchors.centerIn: parent; spacing: 4
                            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: modelData.i; size: 22; color: Theme.accent }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.l; color: Theme.text; font.family: Theme.font; font.pixelSize: 10 } }
                        MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { if (!w.reachable) return; if (modelData.f === "pick") picker.running = true; else w.act(modelData.f); } } } } }

            // ---- received files ----
            Row { width: parent.width
                Text { width: parent.width - openChip.width; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; textFormat: Text.PlainText
                    text: "FROM PHONE · " + w.pretty(w.folder); color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10; font.letterSpacing: 0.8 }
                Rectangle { id: openChip; height: 24; width: oc.implicitWidth + 20; radius: 12; color: ocm.containsMouse ? Theme.tileFillHover : Qt.rgba(1, 1, 1, 0.08)
                    Text { id: oc; anchors.centerIn: parent; text: "Open folder"; color: Theme.text; font.family: Theme.font; font.pixelSize: 10 }
                    MouseArea { id: ocm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.openFolder() } } }
            Rectangle {   // KDE Connect still saves into another folder: one click to route files here
                visible: !w.receiving
                width: parent.width; height: 54; radius: 14; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                Row { anchors.fill: parent; anchors.margins: 10; spacing: 10
                    Icon { anchors.verticalCenter: parent.verticalCenter; name: "download"; size: 20; color: Theme.accent }
                    Text { width: parent.width - 20 - 96 - 20; anchors.verticalCenter: parent.verticalCenter; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; textFormat: Text.PlainText
                        text: w.err !== "" ? w.err : "Phone files currently go to " + (w.incoming !== "" ? w.pretty(w.incoming) : "~/Downloads")
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 11 }
                    Rectangle { width: 96; height: 30; anchors.verticalCenter: parent.verticalCenter; radius: 15; color: Theme.accent; opacity: w.busy ? 0.6 : 1
                        Text { anchors.centerIn: parent; text: w.busy ? "…" : "Receive here"; color: "#101218"; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (w.busy || w.cur === "") return; w.busy = true; setup.running = true; } } } } }
            Text { visible: files.count === 0; width: parent.width; horizontalAlignment: Text.AlignHCenter; height: 30; verticalAlignment: Text.AlignVCenter
                text: files.status === FolderListModel.Ready ? "Nothing received yet. Share a file to this PC from the phone." : "Folder not found yet"
                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 }
            Column { width: parent.width; spacing: 4
                Repeater { model: files
                    delegate: Rectangle {
                        id: fr
                        required property int index
                        required property string fileName
                        required property string filePath
                        required property var fileModified
                        required property real fileSize
                        visible: index < 5
                        width: parent.width; height: visible ? 50 : 0; radius: 12
                        color: fm.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : Theme.tileFill
                        Rectangle { x: 8; y: 7; width: 36; height: 36; radius: 9; color: Qt.rgba(1, 1, 1, 0.08); clip: true
                            Image { anchors.fill: parent; visible: w.isImage(fr.fileName) && status === Image.Ready; fillMode: Image.PreserveAspectCrop
                                asynchronous: true; cache: false; sourceSize: Qt.size(96, 96); smooth: true; mipmap: true
                                source: w.isImage(fr.fileName) && fr.visible ? "file://" + fr.filePath : "" }
                            Icon { anchors.centerIn: parent; name: w.iconFor(fr.fileName); size: 20; color: Theme.textDim; visible: !w.isImage(fr.fileName) } }
                        Column { x: 54; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 54 - 12; spacing: 1
                            Text { width: parent.width; elide: Text.ElideMiddle; textFormat: Text.PlainText; text: fr.fileName; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                            Text { text: w.size(fr.fileSize) + " · " + w.ago(fr.fileModified); color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10 } }
                        MouseArea { id: fm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["xdg-open", fr.filePath]) }
                    } }
            }
        }
    }
}
