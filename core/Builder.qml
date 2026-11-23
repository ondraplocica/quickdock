import QtQuick
import Quickshell
import Quickshell.Io

// Interactive bar builder: a normal (floating) window, NOT a layer surface.
//  - three zones (left / centre / right), each a row of segments, each segment a row of widget chips
//  - drag a chip (or a palette card) onto a gap to place it; drop it on the palette to remove it
//  - edits are a draft; "Apply" writes dock.json once (closing dropdowns first), "Revert" reloads the live bar
//  Open with:  quickshell -p ~/quickdock ipc call dock builder   (or the button on the quick-settings Dock page)
FloatingWindow {
    id: win
    title: "Dock builder"
    implicitWidth: 1180; implicitHeight: 800
    minimumSize: Qt.size(1180, 800); maximumSize: Qt.size(1180, 800)    // fixed size => Hyprland floats + centres it
    color: "#121317"

    // ---------------- data ----------------
    property var zones: ({ left: [], center: [], right: [] })     // zone -> array of segments (arrays of widget ids)
    property string position: "bottom"
    property string style: "bar"
    property var manifests: ({})                                   // id -> {name, description}
    property bool dirty: false
    property string status: ""
    readonly property var zoneNames: [ { k: "left", l: "Left" }, { k: "center", l: "Centre" }, { k: "right", l: "Right" } ]

    readonly property var icons: ({
        workspaces: "grid_view", focusedwindow: "web_asset", clock: "schedule", weather: "partly_cloudy_day", apps: "apps",
        nowplaying: "music_note", sysstats: "monitoring", gpu: "memory_alt", claude: "smart_toy", home: "home", folder: "folder",
        github: "commit", tasks: "checklist", focustimer: "timer", kdeconnect: "smartphone", notifications: "notifications",
        dnd: "do_not_disturb_on", clipboard: "content_paste", notes: "sticky_note_2", screenshot: "screenshot_region",
        recentfiles: "history",
        quicksettings: "tune", qtile: "toggle_on", tray: "inbox", network: "network_check", printer: "print",
        peripherals: "mouse", nextevent: "event_upcoming", privacy: "mic", quickconvert: "currency_exchange",
        tailscale: "lan", syncthing: "sync" })
    function baseId(id) { return id.split(":")[0]; }
    function iconFor(id) { return icons[baseId(id)] || "widgets"; }
    function nameFor(id) {
        const m = manifests[baseId(id)], suffix = id.indexOf(":") >= 0 ? " · " + id.split(":").slice(1).join(":") : "";
        return (m && m.name ? m.name : baseId(id)) + suffix;
    }

    // ---------------- flat list <-> zones (same rules as shell.qml) ----------------
    function parse(flat) {
        const z = { left: [[]], center: [[]], right: [[]] };
        const last = a => a[a.length - 1];
        let zone = "left";
        (flat || []).forEach(id => {
            if (id === "@left" || id === "@center" || id === "@right") { zone = id.slice(1); if (last(z[zone]).length) z[zone].push([]); }
            else if (id === "|") { if (last(z[zone]).length) z[zone].push([]); }
            else last(z[zone]).push(id);
        });
        const out = {};
        Object.keys(z).forEach(k => out[k] = z[k].filter(g => g.length > 0));
        return out;
    }
    function flatten(z) {
        const out = [];
        zoneNames.forEach(zn => {
            out.push("@" + zn.k);
            (z[zn.k] || []).forEach((seg, i) => { if (i) out.push("|"); seg.forEach(id => out.push(id)); });
        });
        return out;
    }
    function placed() { const s = {}; zoneNames.forEach(zn => (zones[zn.k] || []).forEach(seg => seg.forEach(id => s[id] = true))); return s; }
    function available() {
        const have = placed(), ids = Object.keys(manifests).filter(i => i !== "qtile" && !have[i]);
        ids.sort((a, b) => nameFor(a).localeCompare(nameFor(b)));
        return ids;
    }

    // ---------------- edits (always on a deep copy, so the UI rebinds) ----------------
    function copy(z) { const o = {}; zoneNames.forEach(zn => o[zn.k] = (z[zn.k] || []).map(s => s.slice())); return o; }
    function clean(z) { zoneNames.forEach(zn => z[zn.k] = z[zn.k].filter(s => s.length > 0)); return z; }
    // slot = { zone, seg, idx, newSeg }: idx = insert position inside segment `seg`; newSeg => a new segment at index `seg`
    function place(id, slot) {
        const z = copy(zones), TOKEN = "\u0000drop";
        const segs = z[slot.zone];
        if (slot.newSeg) segs.splice(Math.min(slot.seg, segs.length), 0, [TOKEN]);
        else { if (!segs.length) segs.push([]); segs[Math.min(slot.seg, segs.length - 1)].splice(slot.idx, 0, TOKEN); }
        // remove the old occurrence (if the widget was already on the bar), then resolve the token
        let removed = false;
        zoneNames.forEach(zn => z[zn.k].forEach(seg => {
            if (removed) return;
            const i = seg.indexOf(id);
            if (i >= 0) { seg.splice(i, 1); removed = true; }
        }));
        zoneNames.forEach(zn => z[zn.k].forEach(seg => { const i = seg.indexOf(TOKEN); if (i >= 0) seg[i] = id; }));
        setZones(clean(z));
    }
    function remove(id) {
        const z = copy(zones);
        zoneNames.forEach(zn => z[zn.k].forEach(seg => { const i = seg.indexOf(id); if (i >= 0) seg.splice(i, 1); }));
        setZones(clean(z));
    }
    function addDefault(id) {      // click on a palette card: append to the centre zone's last segment
        const segs = zones.center, last = segs.length ? segs.length - 1 : 0;
        place(id, { zone: "center", seg: last, idx: segs.length ? segs[last].length : 0, newSeg: segs.length === 0 });
    }
    function setZones(z) { zones = z; dirty = true; status = ""; if (selected && !placed()[selected]) selected = ""; }

    // ---------------- load / apply / revert ----------------
    function revert() {
        zones = parse(Dock.cfg.widgets || []);
        position = Dock.position; style = Dock.style;
        dirty = false; status = "";
    }
    function apply() {
        Dock.closeAll();
        applyTimer.restart();
        status = "Applying…";
    }
    Timer { id: applyTimer; interval: 450
        onTriggered: {
            Dock.save({ widgets: win.flatten(win.zones), layout: "sections", position: win.position, style: win.style });
            win.dirty = false; win.status = "Applied to the bar";
        } }
    Component.onCompleted: revert()
    onVisibleChanged: if (visible) { manifestProc.running = true; revert(); }

    Process {
        id: manifestProc
        command: ["python3", "-I", "-c", "import json,glob,sys\nout={}\nfor d in sys.argv[1:]:\n    for f in sorted(glob.glob(d+'/*/manifest.json')):\n        try:\n            m=json.load(open(f)); out[m['id']]=m\n        except Exception: pass\nprint(json.dumps(list(out.values())))",
                  String(Qt.resolvedUrl("../widgets")).replace("file://", ""), UserWidgets.dir]
        stdout: StdioCollector { onStreamFinished: {
            try {
                const m = {}; JSON.parse(text).forEach(x => { if (x && x.id) m[x.id] = x; });
                win.manifests = m;
            } catch (e) { console.warn("builder: manifests", e); }
        } }
    }

    // ---------------- drag & drop ----------------
    property string selected: ""           // a widget on the bar whose settings are shown in the shelf area
    function hasSettings(id) { const m = manifests[baseId(id)]; return !!(m && m.settings); }
    property string dragId: ""
    property bool dragging: false
    function startDrag(id, item, mx, my) {
        dragId = id; dragging = true;
        const p = item.mapToItem(root, mx, my);
        ghost.x = p.x - ghost.width / 2; ghost.y = p.y - ghost.height / 2;
    }
    function moveDrag(item, mx, my) {
        const p = item.mapToItem(root, mx, my);
        ghost.x = p.x - ghost.width / 2; ghost.y = p.y - ghost.height / 2;
    }
    function endDrag() {
        if (dragging) ghost.Drag.drop();
        dragging = false; dragId = "";
    }

    // ---------------- visuals ----------------
    component Chip: Rectangle {
        id: chip
        property string wid: ""
        property bool inBar: true
        width: 74; height: 62; radius: 14
        color: ma.containsMouse && !win.dragging ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.07)
        border.width: 1; border.color: win.dragId === wid || (inBar && win.selected === wid) ? Theme.accent : Theme.hairline
        opacity: win.dragging && win.dragId === wid ? 0.35 : 1
        Behavior on color { ColorAnimation { duration: 120 } }
        Column { anchors.centerIn: parent; spacing: 3; width: parent.width - 8
            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: win.iconFor(chip.wid); size: 22; color: Theme.text }
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; textFormat: Text.PlainText
                text: win.nameFor(chip.wid); color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10 } }
        MouseArea {
            id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: win.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property real sx: 0; property real sy: 0; property bool moved: false
            onPressed: m => { sx = m.x; sy = m.y; moved = false; }
            onPositionChanged: m => {
                if (!pressed) return;
                if (!moved && Math.hypot(m.x - sx, m.y - sy) > 14) { moved = true; win.startDrag(chip.wid, ma, m.x, m.y); }
                else if (moved) win.moveDrag(ma, m.x, m.y);
            }
            onReleased: { if (moved) win.endDrag(); else if (chip.inBar) win.selected = (win.selected === chip.wid ? "" : chip.wid); else win.addDefault(chip.wid); }
        }
        // this widget has settings (click it to edit them below)
        Icon { visible: chip.inBar && win.hasSettings(chip.wid); x: 6; y: 4; name: "tune"; size: 12; color: Theme.accent }
        // remove (bar chips only)
        Rectangle {
            visible: chip.inBar && ma.containsMouse && !win.dragging
            width: 18; height: 18; radius: 9; x: parent.width - 14; y: -4
            color: xma.containsMouse ? Theme.bad : "#2a2c33"; border.width: 1; border.color: Theme.hairlineHover
            Icon { anchors.centerIn: parent; name: "close"; size: 12; color: Theme.text }
            MouseArea { id: xma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.remove(chip.wid) }
        }
    }

    // a drop target: thin line that grows + lights up while a chip hovers over it
    component Slot: DropArea {
        id: slot
        property var target: ({})
        property bool vertical: true       // vertical line (between chips) vs horizontal bar (between segments)
        keys: ["w"]
        width: vertical ? (containsDrag ? 22 : 12) : 0
        height: 62
        Behavior on width { NumberAnimation { duration: 110 } }
        onDropped: drop => { drop.accept(); win.place(win.dragId, slot.target); }
        Rectangle { anchors.centerIn: parent; width: 3; height: parent.height - 8; radius: 2
            color: Theme.accent; opacity: slot.containsDrag ? 1 : (win.dragging ? 0.28 : 0) }
    }

    Item {
        id: root
        anchors.fill: parent

        // header
        Item { id: header; x: 28; y: 20; width: parent.width - 56; height: 44
            Column { anchors.verticalCenter: parent.verticalCenter
                Text { text: "Bar builder"; color: Theme.text; font.family: Theme.font; font.pixelSize: 20; font.weight: Font.DemiBold }
                Text { text: "Drag widgets between gaps. Click one for its settings. Drop on the shelf to remove. Apply to update the live bar."
                    color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 } }
            Row { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                Text { anchors.verticalCenter: parent.verticalCenter; text: win.status; color: Theme.good; font.family: Theme.font; font.pixelSize: 12 }
                Rectangle { width: 86; height: 36; radius: 18; color: rma.containsMouse ? Theme.tileFillHover : Qt.rgba(1, 1, 1, 0.07); opacity: win.dirty ? 1 : 0.5
                    Text { anchors.centerIn: parent; text: "Revert"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                    MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true; enabled: win.dirty; cursorShape: Qt.PointingHandCursor; onClicked: win.revert() } }
                Rectangle { width: 96; height: 36; radius: 18; color: Theme.accent; opacity: win.dirty ? 1 : 0.45
                    Text { anchors.centerIn: parent; text: "Apply"; color: "#101218"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                    MouseArea { anchors.fill: parent; enabled: win.dirty; cursorShape: Qt.PointingHandCursor; onClicked: win.apply() } }
            }
        }

        // look: position + style
        Row { id: looks; x: 28; y: 78; spacing: 22
            Row { spacing: 8
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Position"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                Segmented { itemWidth: 84; current: win.position
                    options: [ { l: "Top", v: "top", i: "vertical_align_top" }, { l: "Bottom", v: "bottom", i: "vertical_align_bottom" } ]
                    onPicked: v => { win.position = v; win.dirty = true; } } }
            Row { spacing: 8
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Style"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                Segmented { itemWidth: 96; current: win.style
                    options: [ { l: "Bar", v: "bar", i: "dock_to_bottom" }, { l: "Segments", v: "segments", i: "view_agenda" }, { l: "Pills", v: "pills", i: "pill" } ]
                    onPicked: v => { win.style = v; win.dirty = true; } } }
        }

        // the bar: three zones
        Column { id: bar; x: 28; y: 128; width: parent.width - 56; spacing: 10
            Repeater {
                model: win.zoneNames
                delegate: Rectangle {
                    id: zrow
                    required property var modelData
                    readonly property var segs: win.zones[modelData.k] || []
                    width: bar.width; height: Math.max(94, flow.implicitHeight + 28); radius: 18
                    color: Qt.rgba(0.05, 0.05, 0.07, 0.9); border.width: 1; border.color: Theme.hairline
                    Text { x: 16; y: 8; text: zrow.modelData.l.toUpperCase(); color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10; font.letterSpacing: 1.2 }
                    Flow {
                        id: flow
                        x: 12; y: 26; width: parent.width - 24; spacing: 8
                        // drop target at the very start (new first segment)
                        Slot { target: ({ zone: zrow.modelData.k, seg: 0, idx: 0, newSeg: true }); visible: zrow.segs.length > 0 }
                        Repeater {
                            model: zrow.segs
                            delegate: Row {
                                id: segr
                                required property var modelData
                                required property int index
                                spacing: 0
                                Rectangle {   // one segment
                                    height: 62; radius: 16; color: Qt.rgba(1, 1, 1, 0.035); border.width: 1; border.color: Theme.hairline
                                    width: inner.implicitWidth + 12
                                    Row { id: inner; anchors.centerIn: parent; spacing: 0
                                        Slot { target: ({ zone: zrow.modelData.k, seg: segr.index, idx: 0, newSeg: false }) }
                                        Repeater {
                                            model: segr.modelData
                                            delegate: Row {
                                                required property string modelData
                                                required property int index
                                                spacing: 0
                                                Chip { wid: modelData }
                                                Slot { target: ({ zone: zrow.modelData.k, seg: segr.index, idx: index + 1, newSeg: false }) }
                                            }
                                        }
                                    }
                                }
                                Slot { target: ({ zone: zrow.modelData.k, seg: segr.index + 1, idx: 0, newSeg: true }) }
                            }
                        }
                        // empty zone: one big target
                        Slot { visible: zrow.segs.length === 0; vertical: true; width: 160; height: 62
                            target: ({ zone: zrow.modelData.k, seg: 0, idx: 0, newSeg: true })
                            Text { anchors.centerIn: parent; text: "drop widgets here"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 } }
                    }
                }
            }
        }

        // shelf: available widgets (also the remove target)
        DropArea {
            id: shelf
            x: 28; y: parent.height - 262; width: parent.width - 56; height: 240
            keys: win.selected === "" ? ["w"] : ["w-off"]      // refuse drops (no remove) while the settings panel is up; NOT `enabled`, which would also disable the panel inside
            onDropped: drop => { drop.accept(); if (win.dragId) win.remove(win.dragId); }
            Rectangle { anchors.fill: parent; radius: 18; color: shelf.containsDrag ? Qt.rgba(0.94, 0.33, 0.31, 0.14) : Qt.rgba(1, 1, 1, 0.04)
                border.width: 1; border.color: shelf.containsDrag ? Theme.bad : Theme.hairline
                Behavior on color { ColorAnimation { duration: 120 } } }
            Text { visible: win.selected === ""; x: 16; y: 10; text: shelf.containsDrag ? "RELEASE TO REMOVE FROM THE BAR" : "AVAILABLE WIDGETS · drag onto the bar, or click to add to the centre"
                color: shelf.containsDrag ? Theme.bad : Theme.textDim; font.family: Theme.font; font.pixelSize: 10; font.letterSpacing: 1.2 }
            Flickable {
                visible: win.selected === ""
                x: 12; y: 32; width: parent.width - 24; height: parent.height - 42
                contentHeight: shelfFlow.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                Flow { id: shelfFlow; width: parent.width; spacing: 10
                    Repeater {
                        model: win.available()
                        delegate: Item {
                            required property string modelData
                            width: 128; height: 62
                            Rectangle { anchors.fill: parent; radius: 14; color: pma.containsMouse && !win.dragging ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.07)
                                border.width: 1; border.color: win.dragId === parent.parent.modelData ? Theme.accent : Theme.hairline
                                opacity: win.dragging && win.dragId === parent.parent.modelData ? 0.35 : 1
                                Row { anchors.fill: parent; anchors.margins: 10; spacing: 8
                                    Icon { anchors.verticalCenter: parent.verticalCenter; name: win.iconFor(parent.parent.parent.modelData); size: 22 }
                                    Column { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 34
                                        Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText; text: win.nameFor(parent.parent.parent.parent.modelData)
                                            color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                                        Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
                                            text: (win.manifests[parent.parent.parent.parent.modelData] || {}).description || ""
                                            color: Theme.textDim; font.family: Theme.font; font.pixelSize: 9 } } }
                            }
                            MouseArea {
                                id: pma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.OpenHandCursor
                                property real sx: 0; property real sy: 0; property bool moved: false
                                onPressed: m => { sx = m.x; sy = m.y; moved = false; }
                                onPositionChanged: m => {
                                    if (!pressed) return;
                                    if (!moved && Math.hypot(m.x - sx, m.y - sy) > 14) { moved = true; win.startDrag(parent.modelData, pma, m.x, m.y); }
                                    else if (moved) win.moveDrag(pma, m.x, m.y);
                                }
                                onReleased: { if (moved) win.endDrag(); else win.addDefault(parent.modelData); }
                            }
                        }
                    }
                }
            }
            // ---- per-widget settings (replaces the shelf while a widget on the bar is selected) ----
            Item {
                id: sp
                anchors.fill: parent
                visible: win.selected !== ""
                readonly property bool has: win.hasSettings(win.selected)
                Row { x: 16; y: 10; spacing: 8; height: 26
                    Icon { anchors.verticalCenter: parent.verticalCenter; name: win.selected ? win.iconFor(win.selected) : ""; size: 18; color: Theme.accent }
                    Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: win.selected ? win.nameFor(win.selected) + " settings" : ""
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                    Text { anchors.verticalCenter: parent.verticalCenter; visible: sp.has; text: "saved as you change them (no Apply needed)"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 } }
                IconButton { anchors.right: parent.right; anchors.rightMargin: 10; y: 6; width: 30; height: 30; radius: 15; icon: "close"; onClicked: win.selected = "" }
                Loader {
                    id: sl
                    x: 12; y: 44; width: parent.width - 24; height: parent.height - 52
                    active: sp.visible && sp.has
                    source: active ? UserWidgets.settingsSource(win.baseId(win.selected)) : ""
                }
                Binding { target: sl.item; property: "instanceId"; value: win.selected; when: sl.item !== null }
                Text { visible: !sp.has; anchors.centerIn: parent; text: "This widget has no settings yet."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
            }
        }


        // the dragged chip
        Rectangle {
            id: ghost
            visible: win.dragging
            width: 74; height: 62; radius: 14
            color: Qt.rgba(0.54, 0.7, 1, 0.28); border.width: 2; border.color: Theme.accent
            z: 100
            Drag.active: win.dragging
            Drag.keys: ["w"]
            Drag.hotSpot.x: width / 2; Drag.hotSpot.y: height / 2
            Column { anchors.centerIn: parent; spacing: 3; width: parent.width - 8
                Icon { anchors.horizontalCenter: parent.horizontalCenter; name: win.iconFor(win.dragId); size: 22 }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; textFormat: Text.PlainText
                    text: win.dragId ? win.nameFor(win.dragId) : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 10 } }
        }
    }
}
