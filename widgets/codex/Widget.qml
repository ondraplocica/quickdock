import QtQuick
import Quickshell.Io
import "../../core"

// Codex limit: a glyph inside a ring (percent of the fullest window used) with the percentage next to it; the dropdown
// lists each window (weekly and/or 5-hour), when it resets, the plan and credits.
// Data: codex-limits.py reads the rate limits the Codex CLI logs in its local session files (no network, no login token).
// They update while Codex is being used; otherwise the last reading is shown dimmed.
Tile {
    id: w
    implicitWidth: row.implicitWidth + 28
    property var d: ({})
    readonly property bool ok: d.ok === true
    readonly property real ageSec: d.ts ? Math.max(0, Math.floor(Date.now() / 1000) - d.ts) : 0
    readonly property bool stale: !ok || ageSec > 5400          // last reading older than 90 minutes
    readonly property var windows: d.windows || []
    // a window whose reset time has passed is back to 0 (the recorded number is from before the reset)
    function usedOf(x) { return x.expired ? 0 : x.used; }
    readonly property real used: windows.length ? Math.max.apply(null, windows.map(usedOf)) : 0
    function toggle() { pop.open = !pop.open; }
    onClicked: toggle()
    function tint(v) { return v > 85 ? Theme.bad : (v > 60 ? Theme.warn : Theme.accent); }
    function until(epoch) {
        if (!epoch) return "";
        const m = Math.max(0, Math.round((epoch * 1000 - Date.now()) / 60000));
        const dd = Math.floor(m / 1440), h = Math.floor(m % 1440 / 60);
        return (dd ? dd + "d " : "") + (h ? h + "h " : "") + (m % 60) + "m";
    }
    function ago(s) { return s < 90 ? "just now" : (s < 5400 ? Math.round(s / 60) + " min ago" : (s < 129600 ? Math.round(s / 3600) + " h ago" : Math.round(s / 86400) + " d ago")); }

    Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!proc.running) proc.running = true }
    Process {
        id: proc
        command: ["python3", "-I", String(Qt.resolvedUrl("codex-limits.py")).replace("file://", "")]
        stdout: StdioCollector { onStreamFinished: { try { w.d = JSON.parse(text); } catch (e) {} } }
    }

    Row {
        id: row
        anchors.centerIn: parent; spacing: 8
        opacity: w.stale ? 0.55 : 1
        Item { width: 30; height: 30; anchors.verticalCenter: parent.verticalCenter
            Ring { anchors.fill: parent; size: 30; thickness: 3.5; value: w.used / 100; fill: w.tint(w.used) }
            Image { anchors.centerIn: parent; width: 14; height: 14; source: "codex.svg"; sourceSize: Qt.size(56, 56); smooth: true; mipmap: true } }
        Text { anchors.verticalCenter: parent.verticalCenter; text: w.ok ? Math.round(w.used) + "%" : "--"
            color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold }
    }

    Popover {
        id: pop
        target: w
        panelWidth: 360
        panelHeight: 118 + (w.ok ? w.windows.length * 58 : 40) + (w.ok && w.d.credits && w.d.credits.has_credits ? 22 : 0)
        Column {
            id: card
            anchors { fill: parent; margins: 16 }
            spacing: 14
            Row { spacing: 8
                Text { text: "Codex usage"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
                Rectangle { visible: w.ok && (w.d.plan || "") !== ""; height: 20; width: pl.implicitWidth + 14; radius: 10; color: Theme.tileFill; anchors.verticalCenter: parent.verticalCenter
                    Text { id: pl; anchors.centerIn: parent; textFormat: Text.PlainText; text: w.d.plan || ""; color: Theme.accent; font.family: Theme.font; font.pixelSize: 10; font.capitalization: Font.AllUppercase } } }
            Text { visible: !w.ok; width: card.width; wrapMode: Text.WordWrap; textFormat: Text.PlainText; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12
                text: (w.d.error || "No reading yet") + ". The numbers come from Codex's local session files, so Codex has to have been used once." }
            Repeater {
                model: w.windows
                delegate: Column {
                    id: wr
                    required property var modelData
                    width: card.width; spacing: 5
                    readonly property real u: w.usedOf(modelData)
                    Row { width: parent.width
                        Text { text: wr.modelData.label + " limit"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; width: parent.width / 2 }
                        Text { text: Math.round(wr.u) + "%  ·  " + (wr.modelData.expired ? "reset since last reading" : "resets in " + w.until(wr.modelData.resets_at)); color: Theme.textDim
                            font.family: Theme.font; font.pixelSize: 11; width: parent.width / 2; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight } }
                    Rectangle { width: parent.width; height: 8; radius: 4; color: Theme.tileFill
                        Rectangle { height: 8; radius: 4; color: w.tint(wr.u)
                            width: pop.open ? Math.max(8, parent.width * wr.u / 100) : 0
                            Behavior on width { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } } } }
                }
            }
            Text { visible: w.ok && w.d.credits && w.d.credits.has_credits === true; textFormat: Text.PlainText; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11
                text: "Credits: " + (w.d.credits && w.d.credits.unlimited ? "unlimited" : (w.d.credits ? w.d.credits.balance : "")) }
            Text { visible: w.ok; width: card.width; wrapMode: Text.WordWrap; color: w.stale ? Theme.warn : Theme.textDim; font.family: Theme.font; font.pixelSize: 10
                text: "Last reading " + w.ago(w.ageSec) + ". Updates while Codex is running." }
        }
    }
}
