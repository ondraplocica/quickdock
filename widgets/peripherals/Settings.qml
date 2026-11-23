import QtQuick
import Quickshell.Io
import "../../core"

// Peripherals settings page, shown by the bar builder when the widget is selected (manifest: "settings": true).
// Everything saves straight to dock.json -> widgetConfig.<instanceId>: { hidden, names, showWired, max }.
Item {
    id: s
    property string instanceId: "peripherals"
    readonly property var cfg: (Dock.cfg.widgetConfig || {})[instanceId] || ({})
    readonly property var hidden: cfg.hidden || []
    readonly property var names: cfg.names || ({})
    readonly property bool showWired: cfg.showWired !== false
    readonly property int maxRings: cfg.max || 4
    readonly property string script: String(Qt.resolvedUrl("periph.py")).replace("file://", "")

    property var solaarDevs: []
    property var sysDevs: []
    property bool sysDone: false
    property bool solDone: false
    readonly property var all: {
        const seen = {}, out = [];
        solaarDevs.concat(sysDevs).forEach(d => {
            if (seen[d.name.toLowerCase()]) return;
            seen[d.name.toLowerCase()] = true;
            out.push(Object.assign({}, d, { key: d.name, hiddenNow: hidden.indexOf(d.name) >= 0, shownName: (names[d.name] || "").trim() || d.name }));
        });
        hidden.forEach(h => { if (!seen[String(h).toLowerCase()]) out.push({ key: h, name: h, shownName: (names[h] || "").trim() || h, kind: "", pct: null, state: "absent", hiddenNow: true }); });
        return out;
    }

    function save(patch) { Dock.saveWidget(instanceId, patch); }
    function setHidden(key, hide) { const h = hidden.filter(x => x !== key); if (hide) h.push(key); save({ hidden: h }); }
    function setName(key, text) {
        const n = Object.assign({}, names), t = (text || "").trim();
        if (t && t !== key) n[key] = t; else delete n[key];
        save({ names: n });
    }
    function iconFor(k) {
        switch (k) {
        case "mouse": return "mouse"; case "keyboard": return "keyboard";
        case "headset": case "headphones": case "audio-headset": case "audio-headphones": return "headphones";
        case "gaming-input": return "sports_esports"; case "phone": return "smartphone"; case "tablet": return "tablet";
        case "touchpad": return "touch_app";
        }
        return "devices_other";
    }
    function ago(ts) {
        const s = Math.max(0, Math.floor(Date.now() / 1000) - (ts || 0));
        if (s < 90) return "just now";
        if (s < 5400) return Math.round(s / 60) + " min ago";
        if (s < 129600) return Math.round(s / 3600) + " h ago";
        return Math.round(s / 86400) + " d ago";
    }
    function stateText(d) {
        if (d.state === "asleep") return "Last reading " + ago(d.ts) + (d.pct !== null && d.pct !== undefined ? " · " + d.pct + "%" : "");
        if (d.state === "absent") return "Not detected right now";
        if (d.state === "wired") return "Wired (USB), no battery reading";
        const m = { charging: "Charging", discharging: "On battery", full: "Fully charged" };
        return (m[d.state] || "") + (d.pct !== null && d.pct !== undefined ? (m[d.state] ? " · " : "") + d.pct + "%" : "");
    }

    Component.onCompleted: { sysProc.running = true; solProc.running = true; }
    Process { id: sysProc; command: ["python3", "-I", s.script, "system"]
        stdout: StdioCollector { onStreamFinished: { try { const r = JSON.parse(text); if (r.ok) s.sysDevs = r.devices; } catch (e) {} s.sysDone = true; } } }
    Process { id: solProc; command: ["python3", "-I", s.script, "solaar"]
        stdout: StdioCollector { onStreamFinished: { try { const r = JSON.parse(text); if (r.ok) s.solaarDevs = r.devices; } catch (e) {} s.solDone = true; } } }

    // ---------- device list ----------
    Text { x: 4; y: 0; text: "DEVICES · eye = show on the bar, click a name to rename"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10; font.letterSpacing: 1.2 }
    Text { visible: s.all.length === 0; x: 4; y: 30; width: 640; wrapMode: Text.WordWrap; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12
        text: (s.sysDone && s.solDone) ? "No devices detected. Logitech devices (Solaar), Bluetooth and upower devices appear here." : "Detecting devices… (Logitech via Solaar can take a few seconds)" }
    Flickable {
        x: 0; y: 22; width: 700; height: s.height - 22
        contentHeight: col.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
        Column { id: col; width: parent.width; spacing: 4
            Repeater { model: s.all
                delegate: Item { id: row; required property var modelData; width: col.width; height: 44
                    readonly property bool off: modelData.hiddenNow || (!s.showWired && modelData.state === "wired")
                    opacity: off ? 0.5 : 1
                    Rectangle { anchors.fill: parent; radius: 12; color: Qt.rgba(1, 1, 1, 0.05); border.width: 1; border.color: Theme.hairline }
                    IconButton { x: 6; anchors.verticalCenter: parent.verticalCenter; width: 32; height: 32; radius: 16
                        icon: modelData.hiddenNow ? "visibility_off" : "visibility"; onClicked: s.setHidden(modelData.key, !modelData.hiddenNow) }
                    Icon { x: 46; anchors.verticalCenter: parent.verticalCenter; name: s.iconFor(modelData.kind); size: 18; color: Theme.textDim }
                    TextInput { x: 76; width: 300; anchors.verticalCenter: parent.verticalCenter; clip: true; selectByMouse: true
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                        text: modelData.shownName; onEditingFinished: s.setName(modelData.key, text) }
                    Text { anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText
                        text: s.stateText(modelData); color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 }
                }
            }
        }
    }

    // ---------- options ----------
    Column { x: 730; y: 22; width: s.width - 730; spacing: 8
        Rectangle { width: parent.width; height: 48; radius: 12; color: Qt.rgba(1, 1, 1, 0.05); border.width: 1; border.color: Theme.hairline
            Text { x: 14; anchors.verticalCenter: parent.verticalCenter; text: "Show wired devices (no battery)"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
            Rectangle { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; width: 40; height: 22; radius: 11
                color: s.showWired ? Theme.accent : Qt.rgba(1, 1, 1, 0.14)
                Rectangle { y: 3; x: s.showWired ? 21 : 3; width: 16; height: 16; radius: 8; color: "#fff"; Behavior on x { NumberAnimation { duration: 130 } } }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: s.save({ showWired: !s.showWired }) } } }
        Stepper { label: "Rings on the bar"; valueText: String(s.maxRings)
            onMinus: s.save({ max: Math.max(1, s.maxRings - 1) })
            onPlus: s.save({ max: Math.min(8, s.maxRings + 1) }) }
        Text { width: parent.width; wrapMode: Text.WordWrap; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11
            text: "Hidden devices stay listed here so you can bring them back. The peripherals dropdown has the same options behind its pencil." }
    }
}
