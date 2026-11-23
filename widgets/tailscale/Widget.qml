import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"

// Tailscale: tile shows state + online peer count; dropdown has this node, exit-node chooser,
// connect/disconnect and a peer list (click = copy IP). Read via `tailscale status --json` (ts.py).
Tile {
    id: w
    implicitWidth: row.implicitWidth + 24
    property var st: ({})
    property string msg: ""
    property bool exitOpen: false
    readonly property bool ok: st.ok === true
    readonly property bool running: ok && st.state === "Running"
    readonly property bool operator: ok && st.operator === true
    readonly property string exitNode: ok ? (st.exitNode || "") : ""
    readonly property color stateColor: !ok ? Theme.textDim : (running ? Theme.good : (st.state === "NeedsLogin" ? Theme.warn : Theme.textDim))
    readonly property string script: String(Qt.resolvedUrl("ts.py")).replace("file://", "")
    readonly property string fixCmd: "sudo tailscale set --operator=$USER"

    function toggle() { pop.open = !pop.open; if (pop.open) { exitOpen = false; poll.running = true; } }
    function action(arg) { toggle(); }                       // ipc test hook
    onClicked: toggle()

    function flash(t) { msg = t; msgTimer.restart(); }
    function copy(text) { Quickshell.execDetached(["wl-copy", text]); flash("Copied " + text); }
    function mutate(args) {
        if (!operator) { flash("Needs one-time setup (see above)"); return; }
        if (act.running) return;
        act.command = ["python3", "-I", script].concat(args);
        act.running = true;
    }
    function setExit(ip) { exitOpen = false; mutate(["exit", ip]); }
    function toggleUp() { mutate([running ? "down" : "up"]); }
    function ago(iso) {
        if (!iso || iso.indexOf("0001") === 0) return "never";
        const s = (Date.now() - new Date(iso).getTime()) / 1000;
        if (!(s >= 0)) return "";
        if (s < 90) return "just now";
        if (s < 5400) return Math.round(s / 60) + " min ago";
        if (s < 129600) return Math.round(s / 3600) + " h ago";
        return Math.round(s / 86400) + " d ago";
    }

    Timer { id: msgTimer; interval: 3500; onTriggered: w.msg = "" }
    Timer { interval: pop.open ? 4000 : 20000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!poll.running) poll.running = true }
    Process {
        id: poll
        command: ["python3", "-I", w.script, "status"]
        stdout: StdioCollector { onStreamFinished: { try { w.st = JSON.parse(text); } catch (e) { w.st = ({ ok: false, error: "down" }); } } }
    }
    Process {
        id: act
        stdout: StdioCollector { onStreamFinished: {
            let r = {};
            try { r = JSON.parse(text); } catch (e) { r = { ok: false, error: "failed" }; }
            if (!r.ok) w.flash(r.error === "operator" ? "Needs operator rights (see above)" : "Failed: " + (r.detail || r.error || "unknown"));
            poll.running = true;
        } }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7
        Item { width: 24; height: 24; anchors.verticalCenter: parent.verticalCenter
            Icon { anchors.centerIn: parent; name: w.ok ? "vpn_lock" : "cloud_off"; size: 22; filled: w.running; color: w.running ? Theme.text : Theme.textDim }
            Rectangle { width: 8; height: 8; radius: 4; color: w.stateColor; border.width: 1.5; border.color: Qt.rgba(0, 0, 0, 0.55); anchors { right: parent.right; bottom: parent.bottom; rightMargin: -2; bottomMargin: -1 } } }
        Text { visible: w.running; anchors.verticalCenter: parent.verticalCenter; text: w.running ? w.st.online : ""
            color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
        Icon { visible: w.exitNode !== ""; anchors.verticalCenter: parent.verticalCenter; name: "logout"; size: 15; color: Theme.accent }
    }

    Popover {
        id: pop
        target: w
        panelWidth: 340
        panelHeight: 430
        TsPanel { anchors { fill: parent; margins: 16 } host: w }
    }
}
