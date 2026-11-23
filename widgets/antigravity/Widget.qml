import QtQuick
import Quickshell.Io
import "../../core"

// Antigravity limit: logo inside a ring (percent of the worst 5-hour bucket used) with the percentage next to it.
// Data: agy-quota.py (local Antigravity language server, falls back to the last reading when it is not running).
Tile {
    id: w
    implicitWidth: row.implicitWidth + 28
    property var d: ({})
    readonly property bool ok: d.ok === true
    readonly property bool stale: d.stale !== false
    readonly property var groups: d.groups || []
    // every bucket, flattened, with its group name
    readonly property var buckets: {
        const o = [];
        groups.forEach(g => (g.buckets || []).forEach(b => o.push({ g: g.displayName, id: b.bucketId, win: b.window, rem: b.remainingFraction === undefined ? 0 : b.remainingFraction, reset: b.resetTime })));
        return o;
    }
    // headline = the most used 5-hour bucket (falls back to any bucket)
    readonly property real used: {
        const five = buckets.filter(b => b.win === "5h"), pool = five.length ? five : buckets;
        return pool.length ? 100 * (1 - Math.min.apply(null, pool.map(b => b.rem))) : 0;
    }
    function toggle() { pop.open = !pop.open; }
    onClicked: toggle()
    function tint(v) { return v > 85 ? Theme.bad : (v > 60 ? Theme.warn : Theme.accent); }
    function until(iso) {
        if (!iso) return "";
        const m = Math.max(0, Math.round((new Date(iso).getTime() - Date.now()) / 60000));
        const dd = Math.floor(m / 1440), h = Math.floor(m % 1440 / 60);
        return "resets in " + (dd ? dd + "d " : "") + (h ? h + "h " : "") + (m % 60) + "m";
    }
    function ago(ts) {
        const s = Math.max(0, Math.floor(Date.now() / 1000) - (ts || 0));
        return s < 90 ? "just now" : (s < 5400 ? Math.round(s / 60) + " min ago" : (s < 129600 ? Math.round(s / 3600) + " h ago" : Math.round(s / 86400) + " d ago"));
    }
    function winLabel(b) { return b.win === "5h" ? "5-hour" : (b.win === "weekly" ? "Weekly" : b.win); }

    Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!proc.running) proc.running = true }
    Process {
        id: proc
        command: ["python3", "-I", String(Qt.resolvedUrl("agy-quota.py")).replace("file://", "")]
        stdout: StdioCollector { onStreamFinished: { try { w.d = JSON.parse(text); } catch (e) {} } }
    }

    Row {
        id: row
        anchors.centerIn: parent; spacing: 8
        opacity: w.ok && !w.stale ? 1 : 0.55
        Item { width: 30; height: 30; anchors.verticalCenter: parent.verticalCenter
            Ring { anchors.fill: parent; size: 30; thickness: 3.5; value: w.used / 100; fill: w.tint(w.used) }
            Image { anchors.centerIn: parent; width: 14; height: 14; source: "antigravity.svg"; sourceSize: Qt.size(56, 56); smooth: true; mipmap: true } }
        Text { anchors.verticalCenter: parent.verticalCenter; text: w.ok ? Math.round(w.used) + "%" : "--"
            color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold }
    }

    Popover {
        id: pop
        target: w
        panelWidth: 360
        panelHeight: 70 + w.groups.length * 24 + w.buckets.length * 40
        Column {
            id: card
            anchors { fill: parent; margins: 16 }
            spacing: 12
            Row { spacing: 8
                Text { text: "Antigravity usage"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
                Text { visible: w.ok && w.stale; anchors.verticalCenter: parent.verticalCenter; text: "last reading " + w.ago(w.d.ts); color: Theme.warn; font.family: Theme.font; font.pixelSize: 10 } }
            Text { visible: !w.ok; width: card.width; wrapMode: Text.WordWrap; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12
                text: "No reading yet. The limits come from the local Antigravity server, so Antigravity (or agy) has to be running once." }
            Repeater {
                model: w.groups
                delegate: Column {
                    id: grp
                    required property var modelData
                    width: card.width; spacing: 6
                    Text { text: grp.modelData.displayName; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.6 }
                    Repeater {
                        model: grp.modelData.buckets || []
                        delegate: Column {
                            id: bk
                            required property var modelData
                            readonly property real u: 100 * (1 - (modelData.remainingFraction || 0))
                            width: grp.width; spacing: 4
                            Row { width: parent.width
                                Text { text: w.winLabel({ win: bk.modelData.window }); color: Theme.text; font.family: Theme.font; font.pixelSize: 12; width: parent.width / 2 }
                                Text { text: Math.round(bk.u) + "%  ·  " + w.until(bk.modelData.resetTime); color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11
                                    width: parent.width / 2; horizontalAlignment: Text.AlignRight } }
                            Rectangle { width: parent.width; height: 6; radius: 3; color: Theme.tileFill
                                Rectangle { height: 6; radius: 3; color: w.tint(bk.u)
                                    width: pop.open ? Math.max(6, parent.width * bk.u / 100) : 0
                                    Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } } } }
                        }
                    }
                }
            }
        }
    }
}
