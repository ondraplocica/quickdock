import QtQuick
import Quickshell.Io
import "../../core"

// Peripheral batteries: a row of small rings on the dock, a device list in the dropdown. Not placed on the bar by default.
// Sources: Solaar (MX Master 4), upower, connected Bluetooth devices, plus a "Wired" row for a USB Keychron without a battery source.
// Config (dock.json -> widgetConfig.peripherals): { "hidden": ["Device name", ...], "names": { "Device name": "Pretty name" }, "max": 4, "showWired": true }
// The dropdown's pencil button edits all of this (show/hide each detected device, rename it, toggle wired entries).
Tile {
    id: w
    implicitWidth: row.implicitWidth + 24
    readonly property var cfg: (Dock.cfg.widgetConfig || {}).peripherals || ({})
    readonly property var hidden: cfg.hidden || []
    readonly property var names: cfg.names || ({})
    readonly property int maxRings: cfg.max || 4
    readonly property string script: String(Qt.resolvedUrl("periph.py")).replace("file://", "")
    property var solaarDevs: []
    property var sysDevs: []
    property bool loaded: false
    readonly property bool showWired: cfg.showWired !== false
    property bool editing: false
    // every detected device (deduplicated), with the config key and whether it is currently hidden
    readonly property var allDevices: {
        const seen = {}, out = [];
        solaarDevs.concat(sysDevs).forEach(d => {
            if (seen[d.name.toLowerCase()]) return;
            seen[d.name.toLowerCase()] = true;
            out.push(Object.assign({}, d, { key: d.name, hiddenNow: hidden.indexOf(d.name) >= 0,
                                            shownName: (names[d.name] || "").trim() || d.name }));
        });
        // devices you hid that are not detected right now stay listed in edit mode so they can be restored
        hidden.forEach(h => { if (!seen[String(h).toLowerCase()]) out.push({ key: h, name: h, shownName: (names[h] || "").trim() || h, kind: "", pct: null, state: "absent", hiddenNow: true }); });
        return out;
    }
    readonly property var devices: allDevices.filter(d => !d.hiddenNow && d.state !== "absent" && (showWired || d.state !== "wired"))
                                              .map(d => Object.assign({}, d, { name: d.shownName }))
    function setHidden(key, hide) {
        const h = hidden.filter(x => x !== key);
        if (hide) h.push(key);
        Dock.saveWidget("peripherals", { hidden: h });
    }
    function setName(key, text) {
        const n = Object.assign({}, names), t = (text || "").trim();
        if (t && t !== key) n[key] = t; else delete n[key];
        Dock.saveWidget("peripherals", { names: n });
    }
    function setShowWired(v) { Dock.saveWidget("peripherals", { showWired: v }); }
    onClicked: toggle()
    function toggle() { if (!pop.open) refresh(); pop.open = !pop.open; }
    function openSettings() { toggle(); }
    function refresh() { if (!sysProc.running) sysProc.running = true; if (!solProc.running && Date.now() - lastSolaar > 30000) { lastSolaar = Date.now(); solProc.running = true; } }
    property double lastSolaar: 0

    Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: sysProc.running = true }
    Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: { w.lastSolaar = Date.now(); if (!solProc.running) solProc.running = true; } }
    Process {
        id: sysProc
        command: ["python3", "-I", w.script, "system"]
        stdout: StdioCollector { onStreamFinished: { try { const r = JSON.parse(text); if (r.ok) w.sysDevs = r.devices; } catch (e) {} w.loaded = true; } }
    }
    Process {
        id: solProc
        command: ["python3", "-I", w.script, "solaar"]
        stdout: StdioCollector { onStreamFinished: { try { const r = JSON.parse(text); if (r.ok) w.solaarDevs = r.devices; } catch (e) {} w.loaded = true; } }
    }

    function ringColor(d) { return d.pct === null || d.pct === undefined ? Theme.textDim : (d.pct <= 15 && d.state !== "charging" ? Theme.bad : (d.pct <= 30 && d.state !== "charging" ? Theme.warn : Theme.good)); }
    function iconFor(k) {
        switch (k) {
        case "mouse": return "mouse";
        case "keyboard": return "keyboard";
        case "headset": case "headphones": case "audio-headset": case "audio-headphones": return "headphones";
        case "gaming-input": return "sports_esports";
        case "phone": return "smartphone";
        case "tablet": return "tablet";
        }
        return "devices_other";
    }

    Row { id: row; anchors.centerIn: parent; spacing: 6
        Icon { visible: w.devices.length === 0; name: "devices_other"; size: 22; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
        Repeater { model: w.devices.slice(0, w.maxRings)
            delegate: Item { required property var modelData; width: 30; height: 30; anchors.verticalCenter: parent.verticalCenter
                Ring { anchors.centerIn: parent; size: 30; thickness: 3; value: modelData.pct === null || modelData.pct === undefined ? 0 : modelData.pct / 100; fill: w.ringColor(modelData); endDot: modelData.pct !== null && modelData.pct !== undefined }
                Icon { anchors.centerIn: parent; name: w.iconFor(modelData.kind); size: 14; color: modelData.pct === null || modelData.pct === undefined ? Theme.textDim : Theme.text } } }
    }

    Popover {
        id: pop
        target: w
        panelWidth: list.implicitWidth
        panelHeight: list.implicitHeight
        onOpenChanged: if (!open) w.editing = false
        PeriphList { id: list; anchors.fill: parent; devices: w.devices; loading: !w.loaded
            editing: w.editing; allDevices: w.allDevices; showWired: w.showWired
            onEditToggled: w.editing = !w.editing
            onVisibilityChanged: (key, visible) => w.setHidden(key, !visible)
            onRenameRequested: (key, text) => w.setName(key, text)
            onWiredToggled: v => w.setShowWired(v) }
    }
}
