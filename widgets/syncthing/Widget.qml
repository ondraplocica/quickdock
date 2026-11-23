import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"

// Syncthing: ring tile (progress while syncing, check when idle, warn dot if a device is offline).
// Dropdown lists folders + devices. Read only, via the loopback REST API (st.py reads the key from config.xml).
Tile {
    id: w
    implicitWidth: row.implicitWidth + 22
    property var st: ({})
    readonly property bool ok: st.ok === true
    readonly property string overall: ok ? st.overall : "down"
    readonly property bool busy: overall === "syncing" || overall === "scanning"
    readonly property color stateColor: overall === "idle" ? Theme.good
        : (overall === "syncing" || overall === "scanning" ? Theme.accent
        : (overall === "outofsync" ? Theme.warn : (overall === "error" ? Theme.bad : Theme.textDim)))
    readonly property string script: String(Qt.resolvedUrl("st.py")).replace("file://", "")
    readonly property string label: overall === "idle" ? "Up to date" : (overall === "syncing" ? "Syncing " + st.pct + "%"
        : (overall === "scanning" ? "Scanning" : (overall === "outofsync" ? "Out of sync" : (overall === "error" ? "Error" : "Not running"))))

    function toggle() { pop.open = !pop.open; if (pop.open) poll.running = true; }
    function action(arg) { toggle(); }
    onClicked: toggle()
    function openGui() { if (ok && st.gui) Quickshell.execDetached(["xdg-open", st.gui]); }
    function ago(iso) {
        if (!iso || iso.indexOf("0001") === 0) return "never";
        const s = (Date.now() - new Date(iso).getTime()) / 1000;
        if (!(s >= 0)) return "";
        if (s < 90) return "just now";
        if (s < 5400) return Math.round(s / 60) + " min ago";
        if (s < 129600) return Math.round(s / 3600) + " h ago";
        return Math.round(s / 86400) + " d ago";
    }
    function bytes(b) {
        if (b < 1e6) return Math.round(b / 1000) + " KB";
        if (b < 1e9) return (b / 1e6).toFixed(1) + " MB";
        return (b / 1e9).toFixed(2) + " GB";
    }

    Timer { interval: pop.open ? 3000 : (w.busy ? 4000 : 15000); running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!poll.running) poll.running = true }
    Process {
        id: poll
        command: ["python3", "-I", w.script]
        stdout: StdioCollector { onStreamFinished: { try { w.st = JSON.parse(text); } catch (e) { w.st = ({ ok: false, error: "down" }); } } }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7
        Item { width: 28; height: 28; anchors.verticalCenter: parent.verticalCenter
            Ring { anchors.centerIn: parent; size: 28; thickness: 3.5; value: w.overall === "syncing" ? w.st.pct / 100 : (w.ok ? 1 : 0)
                fill: w.stateColor; track: w.ok ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.10) }
            Icon { anchors.centerIn: parent; size: 15; color: w.stateColor
                name: w.overall === "idle" ? "check" : (w.busy ? "sync" : (w.overall === "error" ? "priority_high" : (w.overall === "outofsync" ? "sync_problem" : "sync_disabled"))) }
            Rectangle { visible: w.ok && w.st.offline > 0; width: 8; height: 8; radius: 4; color: Theme.warn; border.width: 1.5; border.color: Qt.rgba(0, 0, 0, 0.55)
                anchors { right: parent.right; top: parent.top; rightMargin: -2; topMargin: -2 } } }
        Text { visible: w.overall === "syncing"; anchors.verticalCenter: parent.verticalCenter; text: w.st.pct + "%"
            color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
    }

    Popover {
        id: pop
        target: w
        panelWidth: 340
        // grows with the folder/device lists (header + sections + GUI button), capped
        panelHeight: Math.min(560, 150 + (w.ok ? w.st.folders.length * 58 + w.st.devices.length * 46 + (w.st.devices.length ? 22 : 0) : 40) + 42)
        StPanel { anchors { fill: parent; margins: 16 } host: w }
    }
}
