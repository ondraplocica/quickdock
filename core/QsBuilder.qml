import QtQuick
import Quickshell

// Quick-settings builder: a normal floating window (NOT a layer surface), like core/Builder.qml.
//  - left: a miniature of the panel as a stack of modules, in order. Drag a module by its handle to reorder, eye = show/hide.
//    The "Connectivity & toggles" and "Shortcuts" modules contain tile zones: drag tiles between zones / onto gaps.
//  - right: the shelf (tiles not in the panel; also the remove target), tiles that live on the bar (read-only),
//    a form for your own shortcut tiles, and "Reset to defaults".
//  - everything is a draft; Apply writes widgetConfig.quicksettings once (after closing dropdowns). All edits are pure
//    functions in QsLayout, so they can be tested without the UI.
//  Open with:  quickshell -p ~/quickdock ipc call dock qsbuilder   (or the footer pencil of the quick-settings panel)
FloatingWindow {
    id: win
    title: "Quick settings builder"
    implicitWidth: 1180; implicitHeight: 820
    minimumSize: Qt.size(1180, 820); maximumSize: Qt.size(1180, 820)     // fixed size => Hyprland floats + centres it
    color: "#121317"

    // ---------------- draft ----------------
    property var draft: QsLayout.emptyDraft()
    property bool dirty: false
    property string status: ""
    property string notice: ""
    function setDraft(d) { draft = d; dirty = true; status = ""; notice = ""; }
    function revert() { draft = QsLayout.parse(); dirty = false; status = ""; notice = ""; editId = ""; clearForm(); }
    function resetDefaults() { const d = QsLayout.defaultDraft(); d.custom = draft.custom; setDraft(d); }
    Component.onCompleted: revert()
    onVisibleChanged: if (visible) revert()

    readonly property var placedMap: { const m = {}; QsLayout.zoneKeys.forEach(k => draft.zones[k].forEach(id => m[id] = true)); return m; }
    // tiles you can still drop into the panel: catalog tiles not placed / not on the bar, plus unplaced custom tiles
    readonly property var shelfTiles: Quick.ids.filter(id => !placedMap[id] && !draft.docked[id]).concat(draft.custom.map(t => t.id).filter(id => !placedMap[id]))
    readonly property var dockedTiles: Object.keys(draft.docked)

    function placeTile(id, zone, idx) {
        const n = QsLayout.placeTile(draft, id, zone, idx);
        if (!n) { notice = QsLayout.zoneInfo[zone].label + " is full (max " + QsLayout.capacity[zone] + ")"; return; }
        setDraft(n);
    }
    function removeTile(id) { setDraft(QsLayout.removeTile(draft, id)); }
    function addDefault(id) { placeTile(id, "shortcuts", draft.zones.shortcuts.length); }
    function moveMod(mod, idx) { setDraft(QsLayout.moveModule(draft, mod, idx)); }
    function toggleMod(mod) { setDraft(QsLayout.toggleModule(draft, mod)); }

    function apply() {
        Dock.closeAll();
        applyTimer.restart();
        status = "Applying…";
    }
    Timer { id: applyTimer; interval: 450
        onTriggered: { Dock.saveWidget("quicksettings", QsLayout.toConfig(win.draft)); win.dirty = false; win.status = "Applied to the panel"; } }

    // ---------------- custom shortcut tiles ----------------
    property string editId: ""
    function clearForm() { fLabel.text = ""; fIcon.text = ""; fCmd.text = ""; }
    function loadCustom(id) {
        const t = draft.custom.find(x => x.id === id);
        if (!t) return;
        editId = id; fLabel.text = t.label; fIcon.text = t.icon; fCmd.text = t.cmd;
    }
    function validIcon(s) { return /^[a-z0-9_]{1,60}$/.test(s); }
    function saveCustom() {
        const label = fLabel.text.trim(), cmd = fCmd.text.trim(); let icon = fIcon.text.trim().toLowerCase();
        if (!label || !cmd) { notice = "A shortcut needs a name and a command"; return; }
        if (!icon) icon = "bolt";
        if (!validIcon(icon)) { notice = "Icon: a Material Symbols name such as rocket_launch (letters, digits, _)"; return; }
        const n = QsLayout.cloneDraft(draft);
        if (editId) { const t = n.custom.find(x => x.id === editId); if (t) { t.label = label; t.icon = icon; t.cmd = cmd; } }
        else n.custom.push({ id: QsLayout.nextCustomId(draft), label: label, icon: icon, cmd: cmd });
        setDraft(n); editId = ""; clearForm();
    }
    function deleteCustom() {
        if (!editId) return;
        const n = QsLayout.removeTile(draft, editId);
        n.custom = n.custom.filter(t => t.id !== editId);
        setDraft(n); editId = ""; clearForm();
    }
    // the draft's custom tiles must be visible to Quick.meta before Apply, so the builder looks them up itself
    function metaOf(id) {
        const c = Quick.catalog[id];
        if (c) return c;
        const t = draft.custom.find(x => x.id === id);
        return t ? { label: t.label || "Shortcut", icon: t.icon || "bolt" } : { label: id, icon: "help" };
    }

    // ---------------- drag & drop (same scheme as core/Builder.qml) ----------------
    property string dragId: ""
    property string dragKind: ""         // "tile" | "mod"
    property bool dragging: false
    function startDrag(kind, id, item, mx, my) {
        dragKind = kind; dragId = id; dragging = true;
        const p = item.mapToItem(root, mx, my);
        ghost.x = p.x - ghost.width / 2; ghost.y = p.y - ghost.height / 2;
    }
    function moveDrag(item, mx, my) {
        const p = item.mapToItem(root, mx, my);
        ghost.x = p.x - ghost.width / 2; ghost.y = p.y - ghost.height / 2;
    }
    function endDrag() {
        if (dragging) ghost.Drag.drop();
        dragging = false; dragId = ""; dragKind = "";
    }

    // ---------------- building blocks ----------------
    component Chip: Rectangle {
        id: chip
        property string wid: ""
        property bool locked: false          // not draggable / not removable (fixed rows, tiles on the bar)
        property bool removable: false
        property bool onShelf: false
        property string fixedLabel: ""
        property string fixedIcon: ""
        property string badge: ""
        readonly property var m: win.metaOf(wid)
        readonly property bool isCustom: wid.indexOf("c_") === 0
        width: 74; height: 62; radius: 14
        color: ma.containsMouse && !win.dragging && !locked ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.07)
        border.width: 1; border.color: win.dragId === wid && !locked ? Theme.accent : Theme.hairline
        opacity: locked ? 0.5 : (win.dragging && win.dragId === wid ? 0.35 : 1)
        Behavior on color { ColorAnimation { duration: 120 } }
        Column { anchors.centerIn: parent; spacing: 3; width: parent.width - 8
            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: chip.fixedIcon || chip.m.icon; size: 22; color: Theme.text }
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; textFormat: Text.PlainText
                text: chip.fixedLabel || chip.m.label; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10 } }
        Rectangle { visible: chip.badge !== ""; x: 4; y: 4; height: 14; width: bt.implicitWidth + 10; radius: 7; color: Theme.accent
            Text { id: bt; anchors.centerIn: parent; text: chip.badge; color: "#101218"; font.family: Theme.font; font.pixelSize: 8; font.weight: Font.Bold } }
        MouseArea {
            id: ma; anchors.fill: parent; hoverEnabled: true; enabled: !chip.locked
            cursorShape: win.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property real sx: 0; property real sy: 0; property bool moved: false
            onPressed: m => { sx = m.x; sy = m.y; moved = false; }
            onPositionChanged: m => {
                if (!pressed) return;
                if (!moved && Math.hypot(m.x - sx, m.y - sy) > 14) { moved = true; win.startDrag("tile", chip.wid, ma, m.x, m.y); }
                else if (moved) win.moveDrag(ma, m.x, m.y);
            }
            onReleased: { if (moved) win.endDrag(); else if (chip.onShelf) win.addDefault(chip.wid); }
        }
        Rectangle {   // remove (zone chips) / edit (custom chips)
            visible: chip.removable && ma.containsMouse && !win.dragging
            width: 18; height: 18; radius: 9; x: parent.width - 14; y: -4
            color: xma.containsMouse ? Theme.bad : "#2a2c33"; border.width: 1; border.color: Theme.hairlineHover
            Icon { anchors.centerIn: parent; name: "close"; size: 12; color: Theme.text }
            MouseArea { id: xma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.removeTile(chip.wid) }
        }
        Rectangle {
            visible: chip.isCustom && ma.containsMouse && !win.dragging
            width: 18; height: 18; radius: 9; x: -4; y: -4
            color: ema.containsMouse ? Theme.accent : "#2a2c33"; border.width: 1; border.color: Theme.hairlineHover
            Icon { anchors.centerIn: parent; name: "edit"; size: 11; color: ema.containsMouse ? "#101218" : Theme.text }
            MouseArea { id: ema; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.loadCustom(chip.wid) }
        }
    }

    // drop target between tiles
    component TileSlot: DropArea {
        id: ts
        property string zone: "shortcuts"
        property int idx: 0
        property bool big: false
        keys: ["tile"]
        width: big ? 150 : (containsDrag ? 22 : 12)
        height: 62
        Behavior on width { NumberAnimation { duration: 110 } }
        onDropped: drop => { drop.accept(); win.placeTile(win.dragId, ts.zone, ts.idx); }
        Rectangle { visible: !ts.big; anchors.centerIn: parent; width: 3; height: parent.height - 8; radius: 2
            color: Theme.accent; opacity: ts.containsDrag ? 1 : (win.dragging && win.dragKind === "tile" ? 0.28 : 0) }
        Rectangle { visible: ts.big; anchors.fill: parent; radius: 12; color: "transparent"; border.width: 1
            border.color: ts.containsDrag ? Theme.accent : Theme.hairline
            Text { anchors.centerIn: parent; text: "drop tiles here"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 } }
    }

    // a zone of tiles: chips with a drop slot before each and one at the end
    component ZoneFlow: Item {
        id: zf
        property string zone: "top"
        property var fixedRows: []           // [{label, icon}] locked leading chips (Network / Bluetooth)
        property bool wideFirst: false
        readonly property var ids: win.draft.zones[zone]
        width: parent ? parent.width : 0
        implicitHeight: fl.implicitHeight
        Flow {
            id: fl
            width: parent.width; spacing: 4
            Repeater { model: zf.fixedRows
                delegate: Chip { required property var modelData; locked: true; fixedLabel: modelData.label; fixedIcon: modelData.icon } }
            Repeater { model: zf.ids
                delegate: Row {
                    required property string modelData
                    required property int index
                    spacing: 0
                    TileSlot { zone: zf.zone; idx: index }
                    Chip { wid: modelData; removable: true; badge: zf.wideFirst && index === 0 ? "WIDE" : "" }
                } }
            TileSlot { zone: zf.zone; idx: zf.ids.length; big: zf.ids.length === 0 && zf.fixedRows.length === 0 }
        }
    }

    component ZoneLabel: Text {
        property string zone: "top"
        text: (QsLayout.zoneInfo[zone].label + " · " + QsLayout.zoneInfo[zone].hint).toUpperCase()
        color: Theme.textDim; font.family: Theme.font; font.pixelSize: 9; font.letterSpacing: 1
    }

    // drop target between modules
    component ModSlot: DropArea {
        id: ms
        property int idx: 0
        keys: ["mod"]
        width: parent ? parent.width : 0
        height: containsDrag ? 30 : 12
        Behavior on height { NumberAnimation { duration: 110 } }
        onDropped: drop => { drop.accept(); win.moveMod(win.dragId, ms.idx); }
        Rectangle { anchors.centerIn: parent; width: parent.width - 12; height: 3; radius: 2
            color: Theme.accent; opacity: ms.containsDrag ? 1 : (win.dragging && win.dragKind === "mod" ? 0.3 : 0) }
    }

    component Field: Rectangle {
        id: fld
        property alias text: ti.text
        property string hint: ""
        property int maxLen: 200
        height: 34; radius: 10; color: Qt.rgba(1, 1, 1, 0.07); border.width: 1; border.color: ti.activeFocus ? Theme.accent : Theme.hairline
        TextInput { id: ti; anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10; verticalCenter: parent.verticalCenter }
            clip: true; selectByMouse: true; maximumLength: fld.maxLen; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
        Text { visible: ti.text === "" && !ti.activeFocus; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            text: fld.hint; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
    }

    component PillButton: Rectangle {
        id: pb
        property string text: ""
        property bool primary: false
        property bool danger: false
        signal clicked()
        height: 34; width: pt.implicitWidth + 28; radius: 17
        color: primary ? Theme.accent : (danger ? (pma.containsMouse ? Theme.bad : Qt.rgba(0.94, 0.33, 0.31, 0.22)) : (pma.containsMouse ? Theme.tileFillHover : Qt.rgba(1, 1, 1, 0.07)))
        Text { id: pt; anchors.centerIn: parent; text: pb.text; color: pb.primary ? "#101218" : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: pb.primary ? Font.DemiBold : Font.Normal }
        MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pb.clicked() }
    }

    // ---------------- module block contents ----------------
    Component { id: topContent
        Column {
            width: parent ? parent.width : 0; spacing: 6
            ZoneLabel { zone: "conn" }
            ZoneFlow { zone: "conn"; fixedRows: [ { label: "Network", icon: "settings_ethernet" }, { label: "Bluetooth", icon: "bluetooth" } ] }
            ZoneLabel { zone: "top" }
            ZoneFlow { zone: "top"; wideFirst: true }
        } }
    Component { id: shortcutsContent
        Column {
            width: parent ? parent.width : 0; spacing: 6
            ZoneLabel { zone: "shortcuts" }
            ZoneFlow { zone: "shortcuts" }
        } }
    Item {
        id: root
        anchors.fill: parent

        // header
        Item { id: header; x: 28; y: 20; width: parent.width - 56; height: 44
            Column { anchors.verticalCenter: parent.verticalCenter
                Text { text: "Quick settings builder"; color: Theme.text; font.family: Theme.font; font.pixelSize: 20; font.weight: Font.DemiBold }
                Text { text: win.notice !== "" ? win.notice : "Drag modules by the handle, tiles between gaps. Drop a tile on the shelf to remove it. Apply updates the panel."
                    color: win.notice !== "" ? Theme.warn : Theme.textDim; font.family: Theme.font; font.pixelSize: 12 } }
            Row { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                Text { anchors.verticalCenter: parent.verticalCenter; text: win.status; color: Theme.good; font.family: Theme.font; font.pixelSize: 12 }
                PillButton { text: "Revert"; opacity: win.dirty ? 1 : 0.5; enabled: win.dirty; onClicked: win.revert() }
                PillButton { text: "Apply"; primary: true; opacity: win.dirty ? 1 : 0.45; enabled: win.dirty; onClicked: win.apply() }
            }
        }

        // ---------------- left: the panel as a stack of modules ----------------
        Text { x: 28; y: 78; text: "PANEL · top to bottom"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10; font.letterSpacing: 1.2 }
        Flickable {
            id: stackView
            x: 28; y: 98; width: 560; height: parent.height - 98 - 24
            contentHeight: stack.implicitHeight + 8; clip: true; boundsBehavior: Flickable.StopAtBounds
            Column {
                id: stack
                width: stackView.width
                Repeater {
                    model: win.draft.order
                    delegate: Column {
                        id: mrow
                        required property string modelData
                        required property int index
                        width: stack.width
                        readonly property var info: QsLayout.modules[modelData]
                        readonly property bool hiddenMod: win.draft.hiddenMods.indexOf(modelData) >= 0
                        ModSlot { idx: mrow.index }
                        Rectangle {
                            width: parent.width; height: mbody.implicitHeight + 24; radius: 18
                            color: Qt.rgba(0.05, 0.05, 0.07, 0.9); border.width: 1
                            border.color: win.dragId === mrow.modelData && win.dragKind === "mod" ? Theme.accent : Theme.hairline
                            opacity: win.dragging && win.dragKind === "mod" && win.dragId === mrow.modelData ? 0.35 : (mrow.hiddenMod ? 0.5 : 1)
                            Column {
                                id: mbody
                                x: 14; y: 12; width: parent.width - 28; spacing: 8
                                Item { width: parent.width; height: 28
                                    Rectangle { id: handle; width: 28; height: 28; radius: 14; color: hma.containsMouse ? Theme.tileFillHover : "transparent"
                                        Icon { anchors.centerIn: parent; name: "drag_indicator"; size: 19; color: Theme.textDim }
                                        MouseArea {
                                            id: hma; anchors.fill: parent; hoverEnabled: true; cursorShape: win.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                            property real sx: 0; property real sy: 0; property bool moved: false
                                            onPressed: m => { sx = m.x; sy = m.y; moved = false; }
                                            onPositionChanged: m => {
                                                if (!pressed) return;
                                                if (!moved && Math.abs(m.x - sx) + Math.abs(m.y - sy) > 6) { moved = true; win.startDrag("mod", mrow.modelData, hma, m.x, m.y); }
                                                else if (moved) win.moveDrag(hma, m.x, m.y);
                                            }
                                            onReleased: if (moved) win.endDrag()
                                        } }
                                    Icon { x: 34; anchors.verticalCenter: parent.verticalCenter; name: mrow.info.icon; size: 18; color: Theme.text }
                                    Text { x: 58; anchors.verticalCenter: parent.verticalCenter; text: mrow.info.label; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                                    Text { visible: !mrow.info.tiles; x: 160; width: parent.width - 160 - 110; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                                        text: mrow.info.desc; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 }
                                    Text { visible: mrow.hiddenMod; anchors.right: eye.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                                        text: "hidden"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 }
                                    IconButton { id: eye; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 30; height: 30; radius: 15
                                        icon: mrow.hiddenMod ? "visibility_off" : "visibility"; onClicked: win.toggleMod(mrow.modelData) }
                                }
                                Loader {
                                    width: parent.width
                                    active: mrow.info.tiles
                                    sourceComponent: mrow.modelData === "top" ? topContent : shortcutsContent
                                }
                            }
                        }
                    }
                }
                ModSlot { idx: win.draft.order.length }
            }
        }

        // ---------------- right: shelf ----------------
        DropArea {
            id: shelf
            x: 620; y: 98; width: parent.width - 620 - 28; height: 224
            keys: ["tile"]
            onDropped: drop => { drop.accept(); if (win.dragId) win.removeTile(win.dragId); }
            Rectangle { anchors.fill: parent; radius: 18; color: shelf.containsDrag ? Qt.rgba(0.94, 0.33, 0.31, 0.14) : Qt.rgba(1, 1, 1, 0.04)
                border.width: 1; border.color: shelf.containsDrag ? Theme.bad : Theme.hairline
                Behavior on color { ColorAnimation { duration: 120 } } }
            Text { x: 16; y: 10; text: shelf.containsDrag ? "RELEASE TO REMOVE FROM THE PANEL" : "SHELF · drag onto the panel, or click to add to Shortcuts"
                color: shelf.containsDrag ? Theme.bad : Theme.textDim; font.family: Theme.font; font.pixelSize: 10; font.letterSpacing: 1.2 }
            Flickable {
                x: 12; y: 34; width: parent.width - 24; height: parent.height - 44
                contentHeight: shelfFlow.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                Flow { id: shelfFlow; width: parent.width; spacing: 8
                    Repeater { model: win.shelfTiles; delegate: Chip { required property string modelData; wid: modelData; onShelf: true } }
                    Text { visible: win.shelfTiles.length === 0; text: "Every tile is on the panel or on the bar."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                }
            }
        }

        // tiles that live on the bar
        Rectangle {
            x: 620; y: 334; width: parent.width - 620 - 28; height: 100; radius: 18; color: Qt.rgba(1, 1, 1, 0.025); border.width: 1; border.color: Theme.hairline
            Text { x: 16; y: 10; text: "ON THE BAR · managed in the bar builder"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10; font.letterSpacing: 1.2 }
            Flow { x: 12; y: 30; width: parent.width - 24; spacing: 6
                Repeater { model: win.dockedTiles; delegate: Chip { required property string modelData; wid: modelData; locked: true } }
                Text { visible: win.dockedTiles.length === 0; text: "No quick tiles are pinned to the bar."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12; topPadding: 12 } }
        }

        // new / edit shortcut
        Rectangle {
            x: 620; y: 446; width: parent.width - 620 - 28; height: 262; radius: 18; color: Qt.rgba(1, 1, 1, 0.04); border.width: 1; border.color: Theme.hairline
            Text { x: 16; y: 10; text: win.editId ? "EDIT SHORTCUT" : "NEW SHORTCUT · runs your command when clicked"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10; font.letterSpacing: 1.2 }
            Column { x: 16; y: 34; width: parent.width - 32; spacing: 8
                Field { id: fLabel; width: parent.width; hint: "Name, e.g. Screenshot"; maxLen: 24 }
                Row { width: parent.width; spacing: 8
                    Field { id: fIcon; width: parent.width - 46; hint: "Icon name, e.g. photo_camera (Material Symbols)"; maxLen: 60 }
                    Rectangle { width: 38; height: 34; radius: 10; color: Qt.rgba(1, 1, 1, 0.07)
                        Icon { anchors.centerIn: parent; name: win.validIcon(fIcon.text.trim().toLowerCase()) ? fIcon.text.trim().toLowerCase() : "bolt"; size: 20 } } }
                Field { id: fCmd; width: parent.width; hint: "Command, e.g. grim -g \"$(slurp)\" - | wl-copy"; maxLen: 300 }
                Text { width: parent.width; wrapMode: Text.WordWrap; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10
                    text: "Runs with sh -c as you, only when you click the tile. Browse icon names at fonts.google.com/icons." }
                Row { spacing: 8
                    PillButton { text: win.editId ? "Update" : "Add shortcut"; primary: true; onClicked: win.saveCustom() }
                    PillButton { visible: win.editId !== ""; text: "Delete"; danger: true; onClicked: win.deleteCustom() }
                    PillButton { visible: win.editId !== "" || fLabel.text !== "" || fCmd.text !== ""; text: "Clear"; onClicked: { win.editId = ""; win.clearForm(); } }
                }
            }
        }

        PillButton { x: 620; y: 722; text: "Reset layout to defaults"; onClicked: win.resetDefaults() }
        Text { x: 818; y: 730; width: parent.width - 818 - 28; text: "Your own shortcuts are kept (they just go back to the shelf)."; wrapMode: Text.WordWrap
            color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10 }

        // the dragged chip
        Rectangle {
            id: ghost
            visible: win.dragging
            width: win.dragKind === "mod" ? 190 : 74; height: win.dragKind === "mod" ? 38 : 62; radius: win.dragKind === "mod" ? 19 : 14
            color: Qt.rgba(0.54, 0.7, 1, 0.28); border.width: 2; border.color: Theme.accent
            z: 100
            Drag.active: win.dragging
            Drag.keys: [win.dragKind === "mod" ? "mod" : "tile"]
            Drag.hotSpot.x: width / 2; Drag.hotSpot.y: height / 2
            Column { visible: win.dragKind === "tile"; anchors.centerIn: parent; spacing: 3; width: parent.width - 8
                Icon { anchors.horizontalCenter: parent.horizontalCenter; name: win.dragId ? win.metaOf(win.dragId).icon : ""; size: 22 }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; textFormat: Text.PlainText
                    text: win.dragId ? win.metaOf(win.dragId).label : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 10 } }
            Row { visible: win.dragKind === "mod"; anchors.centerIn: parent; spacing: 8
                Icon { anchors.verticalCenter: parent.verticalCenter; name: win.dragKind === "mod" && win.dragId ? QsLayout.modules[win.dragId].icon : ""; size: 18 }
                Text { anchors.verticalCenter: parent.verticalCenter; text: win.dragKind === "mod" && win.dragId ? QsLayout.modules[win.dragId].label : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold } }
        }
    }
}
