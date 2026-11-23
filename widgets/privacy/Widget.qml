import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../../core"

// Privacy indicator: invisible (zero width) while idle; shows an orange mic and/or green camera glyph while an
// app is recording / using the camera. Click lists the apps. Detection is privacy.py (running PipeWire capture
// streams + processes holding /dev/video*), re-run immediately whenever the PipeWire graph changes and every 3 s.
// Config (dock.json -> widgetConfig.privacy): { "ignore": ["some-app"], "alwaysShow": false }
Tile {
    id: w
    readonly property var pc: (Dock.cfg.widgetConfig || {})[instanceId || "privacy"] || config || ({})
    readonly property var ignore: Array.isArray(pc.ignore) ? pc.ignore.map(String) : []
    readonly property string script: String(Qt.resolvedUrl("privacy.py")).replace("file://", "")

    property var mic: []
    property var cam: []
    property var quiet: []     // allowlisted / monitor streams: shown dimmed in the dropdown, never hidden
    readonly property bool inUse: mic.length > 0 || cam.length > 0
    readonly property bool shown: inUse || !!pc.alwaysShow || pop.open
    visible: shown
    implicitWidth: shown ? row.implicitWidth + 20 : 0
    active: false
    function toggle() { pop.open = !pop.open; }
    onClicked: toggle()

    // ---------- detection ----------
    function poll() { if (!pp.running) { pp.command = ["python3", "-I", script].concat(ignore); pp.running = true; } }
    Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: w.poll() }
    Timer { id: soon; interval: 350; onTriggered: w.poll() }
    Connections { target: Pipewire.nodes; function onValuesChanged() { soon.restart(); } }   // an app opened / closed a stream
    Process {
        id: pp
        stdout: StdioCollector { onStreamFinished: {
            try {
                const r = JSON.parse(text);
                if (r.ok) {
                    if (JSON.stringify(r.mic) !== JSON.stringify(w.mic)) w.mic = r.mic;
                    if (JSON.stringify(r.cam) !== JSON.stringify(w.cam)) w.cam = r.cam;
                    const q = r.quiet || [];
                    if (JSON.stringify(q) !== JSON.stringify(w.quiet)) w.quiet = q;
                }
            } catch (e) { } } }
    }

    // ---------- bar glyphs ----------
    Row { id: row; anchors.centerIn: parent; spacing: 6
        Rectangle { visible: w.mic.length > 0; width: 28; height: 28; radius: 14; anchors.verticalCenter: parent.verticalCenter
            color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.20); border.width: 1; border.color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.55)
            Icon { anchors.centerIn: parent; name: "mic"; size: 18; filled: true; color: Theme.warn
                SequentialAnimation on opacity { running: w.mic.length > 0; loops: Animation.Infinite
                    NumberAnimation { to: 0.55; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine } } } }
        Rectangle { visible: w.cam.length > 0; width: 28; height: 28; radius: 14; anchors.verticalCenter: parent.verticalCenter
            color: Qt.rgba(Theme.good.r, Theme.good.g, Theme.good.b, 0.20); border.width: 1; border.color: Qt.rgba(Theme.good.r, Theme.good.g, Theme.good.b, 0.55)
            Icon { anchors.centerIn: parent; name: "videocam"; size: 18; filled: true; color: Theme.good } }
        Icon { visible: !w.inUse; anchors.verticalCenter: parent.verticalCenter; name: "shield"; size: 20; color: Theme.textDim }
    }

    // ---------- dropdown ----------
    readonly property int rowsN: Math.max(1, mic.length + cam.length)
    Popover {
        id: pop
        target: w
        panelWidth: 310
        panelHeight: 62 + (w.quiet.length ? 34 + w.quiet.length * 22 : 0) + (w.inUse ? (w.mic.length ? 30 + w.mic.length * 26 + 8 : 0) + (w.cam.length ? 30 + w.cam.length * 26 + 8 : 0) : 54)
        Item {
            anchors.fill: parent
            Text { x: 16; y: 14; text: "Privacy"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
            Column { x: 16; y: 48; width: parent.width - 32; spacing: 8
                Column { visible: w.mic.length > 0; width: parent.width; spacing: 4
                    Row { spacing: 8
                        Icon { name: "mic"; size: 18; filled: true; color: Theme.warn; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Microphone in use"; color: Theme.warn; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter } }
                    Repeater { model: w.mic
                        delegate: Text { required property string modelData; x: 26; width: parent.width - 26; height: 22; elide: Text.ElideRight
                            text: modelData; textFormat: Text.PlainText; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter } } }
                Column { visible: w.cam.length > 0; width: parent.width; spacing: 4
                    Row { spacing: 8
                        Icon { name: "videocam"; size: 18; filled: true; color: Theme.good; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Camera in use"; color: Theme.good; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter } }
                    Repeater { model: w.cam
                        delegate: Text { required property string modelData; x: 26; width: parent.width - 26; height: 22; elide: Text.ElideRight
                            text: modelData; textFormat: Text.PlainText; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter } } }
                Column { visible: w.quiet.length > 0; width: parent.width; spacing: 2
                    Text { text: "Also active (usually harmless)"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11; height: 20 }
                    Repeater { model: w.quiet
                        delegate: Text { required property var modelData; x: 8; width: parent.width - 8; height: 20; elide: Text.ElideRight; opacity: 0.7
                            text: (modelData.kind === "cam" ? "camera · " : "mic · ") + modelData.name; textFormat: Text.PlainText
                            color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter } } }
                Row { visible: !w.inUse; spacing: 8
                    Icon { name: "verified_user"; size: 22; color: Theme.good; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Nothing is using your mic or camera"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter } }
            }
        }
    }
}
