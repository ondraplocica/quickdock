import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"

// Screen recorder: click to open the dropdown and start (screen / region / window), click again while recording to stop.
// The tile shows a red dot and the elapsed time while recording. Needs wf-recorder (or wl-screenrec); region needs slurp.
// widgetConfig.recorder = { "dir": "~/Videos/Recordings", "defaultMode": "screen", "audio": false }
// `quickshell ipc call dock toggle recorder` starts (defaultMode) or stops, handy for a keybind.
Tile {
    id: w
    implicitWidth: row.implicitWidth + 24
    readonly property string home: Quickshell.env("HOME")
    readonly property var live: (Dock.cfg.widgetConfig || {})[w.instanceId || "recorder"] || ({})
    readonly property string dirCfg: String(live.dir ?? "~/Videos/Recordings").replace(/\/+$/, "")
    readonly property string dir: dirCfg.indexOf("~/") === 0 ? home + dirCfg.slice(1) : dirCfg
    readonly property string defaultMode: ["screen", "region", "window"].indexOf(live.defaultMode) >= 0 ? live.defaultMode : "screen"
    readonly property bool audio: live.audio === true
    property bool recording: false
    property real started: 0
    property string file: ""
    property string err: ""
    property string chosen: ""
    property bool backendsKnown: false
    property real now: Date.now()
    active: recording
    readonly property alias menu: pop       // the dropdown (for tests / scripting)
    readonly property string helper: String(Qt.resolvedUrl("recorder.py")).replace("file://", "")

    function elapsed() {
        const s = Math.max(0, Math.floor((now - started * 1000) / 1000)), h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), c = s % 60;
        const p = n => (n < 10 ? "0" : "") + n;
        return (h ? h + ":" + p(m) : p(m)) + ":" + p(c);
    }
    function toggle() { if (recording) stopRec(); else startRec(defaultMode); }
    onClicked: { if (recording) stopRec(); else pop.open = !pop.open; }
    function startRec(mode) {
        if (act.running || !chosen) return;
        err = "";
        pop.open = false;
        act.args = ["start", mode, audio ? "1" : "0", dir];
        act.kind = "start";
        startDelay.restart();
    }
    function stopRec() { if (act.running) return; act.args = ["stop"]; act.kind = "stop"; act.running = true; }
    function pollNow() { if (!stat.running) stat.running = true; }
    function openFolder() { Quickshell.execDetached(["xdg-open", dir]); }

    Timer { id: startDelay; interval: 350; onTriggered: act.running = true }     // let the dropdown close before capturing
    Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: w.pollNow() }
    Timer { interval: 1000; running: w.recording; repeat: true; onTriggered: w.now = Date.now() }
    Process {
        id: stat
        command: ["python3", "-I", w.helper, "status"]
        stdout: StdioCollector { onStreamFinished: {
            try {
                const r = JSON.parse(text);
                w.recording = r.recording === true;
                if (w.recording) { w.started = r.started; w.file = r.file; w.now = Date.now(); }
            } catch (e) {}
        } }
    }
    Process {
        id: be
        command: ["python3", "-I", w.helper, "backends"]
        running: true
        stdout: StdioCollector { onStreamFinished: { try { w.chosen = JSON.parse(text).chosen || ""; } catch (e) {} w.backendsKnown = true; } }
    }
    Process {
        id: act
        property var args: []
        property string kind: ""
        command: ["python3", "-I", w.helper].concat(args)
        stdout: StdioCollector { onStreamFinished: {
            try {
                const r = JSON.parse(text);
                if (!r.ok) { if (r.error !== "cancelled") w.err = r.error || "failed"; }
                else if (act.kind === "stop") { recents.recheck(); w.recording = false; }
            } catch (e) { w.err = "helper failed"; }
            w.pollNow();
        } }
    }

    DirModel { id: recents; path: w.dir; nameFilters: ["*.mp4", "*.mkv", "*.webm"] }

    Row {
        id: row
        anchors.centerIn: parent; spacing: 8
        Icon { anchors.verticalCenter: parent.verticalCenter; name: w.recording ? "fiber_manual_record" : "videocam"; size: 22; filled: w.recording
            color: w.recording ? Theme.bad : Theme.text
            SequentialAnimation on opacity { running: w.recording; loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 700 } NumberAnimation { to: 1; duration: 700 } }
            onVisibleChanged: if (!w.recording) opacity = 1 }
        Text { visible: w.recording; anchors.verticalCenter: parent.verticalCenter; text: w.elapsed()
            color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
    }

    Popover {
        id: pop
        target: w
        panelWidth: 340
        panelHeight: 196 + (w.err !== "" ? 30 : 0) + (recents.count === 0 ? 40 : Math.min(recents.count, 4) * 50 + 8)
        onOpenChanged: if (open) { recents.recheck(); w.err = ""; }
        Column { anchors { fill: parent; margins: 16 } spacing: 12
            Row { width: parent.width
                Text { width: parent.width - 100; text: "Screen recorder"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
                Text { width: 100; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight; textFormat: Text.PlainText
                    text: w.chosen !== "" ? w.chosen : ""; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10 } }
            Text { visible: w.backendsKnown && w.chosen === ""; width: parent.width; wrapMode: Text.WordWrap
                color: Theme.warn; font.family: Theme.font; font.pixelSize: 11
                text: "No screen recorder found. Install wf-recorder (and slurp for regions), then reopen this." }
            Row { spacing: 8; opacity: w.chosen !== "" ? 1 : 0.4
                Repeater { model: [ { l: "Screen", i: "desktop_windows", m: "screen" }, { l: "Region", i: "crop", m: "region" }, { l: "Window", i: "web_asset", m: "window" } ]
                    delegate: Rectangle { required property var modelData
                        width: 92; height: 62; radius: 14; color: Theme.tileFill
                        scale: bm.pressed ? 0.94 : (bm.containsMouse ? 1.05 : 1)
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                        Column { anchors.centerIn: parent; spacing: 4
                            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: modelData.i; size: 22; color: Theme.accent }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.l; color: Theme.text; font.family: Theme.font; font.pixelSize: 10 } }
                        MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.startRec(modelData.m) } } } }
            Row { width: parent.width; visible: w.chosen === "wf-recorder"
                Text { width: parent.width - 48; anchors.verticalCenter: parent.verticalCenter; text: "Record audio (default input)"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                Rectangle { width: 40; height: 22; radius: 11; anchors.verticalCenter: parent.verticalCenter; color: w.audio ? Theme.accent : Qt.rgba(1, 1, 1, 0.14)
                    Rectangle { y: 3; x: w.audio ? 21 : 3; width: 16; height: 16; radius: 8; color: "#fff"; Behavior on x { NumberAnimation { duration: 130 } } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Dock.saveWidget(w.instanceId || "recorder", { audio: !w.audio }) } } }
            Text { visible: w.err !== ""; width: parent.width; wrapMode: Text.WordWrap; color: Theme.bad; font.family: Theme.font; font.pixelSize: 11; text: w.err }
            Row { width: parent.width
                Text { width: parent.width - oc.width; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; textFormat: Text.PlainText
                    text: "RECENT · " + (w.dir.indexOf(w.home) === 0 ? "~" + w.dir.slice(w.home.length) : w.dir); color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10; font.letterSpacing: 0.8 }
                Rectangle { id: oc; height: 24; width: ot.implicitWidth + 20; radius: 12; color: om.containsMouse ? Theme.tileFillHover : Qt.rgba(1, 1, 1, 0.08)
                    Text { id: ot; anchors.centerIn: parent; text: "Open folder"; color: Theme.text; font.family: Theme.font; font.pixelSize: 10 }
                    MouseArea { id: om; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.openFolder() } } }
            Text { visible: recents.count === 0; width: parent.width; horizontalAlignment: Text.AlignHCenter; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11
                text: "No recordings yet" }
            Column { width: parent.width; spacing: 4
                Repeater { model: recents.items
                    delegate: Rectangle {
                        id: rr
                        required property int index
                        required property string fileName
                        required property string filePath
                        required property real fileSize
                        required property var fileModified
                        visible: index < 4
                        width: parent.width; height: visible ? 46 : 0; radius: 12
                        color: rm.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : Theme.tileFill
                        Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: "movie"; size: 20; color: Theme.textDim }
                        Column { x: 44; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 56; spacing: 1
                            Text { width: parent.width; elide: Text.ElideMiddle; textFormat: Text.PlainText; text: rr.fileName; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                            Text { text: (rr.fileSize >= 1048576 ? (rr.fileSize / 1048576).toFixed(1) + " MB" : Math.round(rr.fileSize / 1024) + " kB") + " · " + Qt.formatDateTime(rr.fileModified, "d MMM HH:mm")
                                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10 } }
                        MouseArea { id: rm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["xdg-open", rr.filePath]) }
                    } }
            }
        }
    }
}
