import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../core"

// Pinned + running apps. Pins live in dock.json -> widgetConfig.apps.pinned (desktop entry ids).
Tile {
    id: w
    interactive: false
    color: Dock.style === "pills" ? Theme.dockFill : "transparent"
    border.width: Dock.style === "pills" ? 1 : 0
    implicitWidth: row.implicitWidth + 8

    readonly property var pinned: ((Dock.cfg.widgetConfig || {}).apps || {}).pinned || []
    readonly property var hidden: ((Dock.cfg.widgetConfig || {}).apps || {}).hidden || []
    property bool showHidden: false
    property var list: []
    property var menuApp: null
    property bool hovering: false
    property string hoverName: ""
    // Popups must never anchor to delegates (they get destroyed on rebuild -> compositor-side crash).
    // These two invisible items live as long as the widget and are moved under the icon instead.
    Item { id: tipAnchor; readonly property real extra: (Dock.popGap - 2) / Dock.uiScale
        y: Dock.popBelow ? 0 : -extra; width: 1; height: w.height + extra }
    Item { id: menuAnchor; y: 0; width: 1; height: w.height }
    property string query: ""

    function toggle() { picker.open = !picker.open; if (picker.open) searchField.forceActiveFocus(); }

    // ---- model: pinned apps first, then running-but-unpinned ones ----
    function rebuild() {
        hovering = false;                 // the hovered icon may be about to be destroyed
        const groups = {};
        ToplevelManager.toplevels.values.forEach(t => {
            const e = DesktopEntries.heuristicLookup(t.appId);
            const id = e ? e.id : t.appId;
            (groups[id] = groups[id] || { entry: e, wins: [] }).wins.push(t);
        });
        const out = [];
        pinned.forEach(id => {
            const e = DesktopEntries.byId(id);
            if (!e) return;
            out.push({ id: id, entry: e, name: e.name, icon: e.icon, wins: groups[id] ? groups[id].wins : [], pinned: true });
            delete groups[id];
        });
        Object.keys(groups).forEach(id => {
            if (hidden.indexOf(id) >= 0) return;          // hidden apps don't get a dock icon
            const g = groups[id];
            out.push({ id: id, entry: g.entry, name: g.entry ? g.entry.name : id, icon: g.entry ? g.entry.icon : id.toLowerCase(),
                       wins: g.wins, pinned: false });
        });
        list = out;
    }
    Component.onCompleted: rebuild()
    Connections { target: Dock; function onCloseAll() { w.hovering = false; menu.open = false; picker.open = false; } }
    onPinnedChanged: rebuild()
    onHiddenChanged: rebuild()
    Connections { target: ToplevelManager.toplevels; function onValuesChanged() { w.rebuild(); } }
    Connections { target: DesktopEntries.applications; function onValuesChanged() { w.rebuild(); } }
    // (focus dots are bindings on each toplevel's `activated`, so no periodic rebuild is needed)

    function setPinned(id, on) {
        const p = pinned.filter(x => x !== id);
        if (on) p.push(id);
        Dock.saveWidget("apps", { pinned: p });
    }
    // Hiding removes an app from the picker and from the running-apps strip; pinning it again brings it back.
    function setHidden(id, on) {
        const h = hidden.filter(x => x !== id);
        if (on) h.push(id);
        Dock.saveWidget("apps", { hidden: h });
        if (on && pinned.indexOf(id) >= 0) setPinned(id, false);
    }
    function activate(app) {
        if (app.wins.length === 0) { app.entry.execute(); return false; }
        const i = app.wins.findIndex(t => t.activated);
        const t = app.wins[(i + 1) % app.wins.length];     // click again to cycle windows
        t.minimized = false;
        t.activate();
        return true;
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        Repeater {
            model: w.list
            delegate: Item {
                id: app
                required property var modelData
                readonly property bool running: modelData.wins.length > 0
                readonly property bool focused: modelData.wins.some(t => t.activated)
                property bool bouncing: false
                Component.onDestruction: w.hovering = false
                width: 46; height: Theme.tileHeight - 4

                Timer { id: bounceStop; interval: 3500; onTriggered: app.bouncing = false }

                Image {
                    id: img
                    width: 34; height: 34
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 5
                    sourceSize: Qt.size(136, 136)
                    smooth: true; mipmap: true; asynchronous: true
                    source: Quickshell.iconPath(modelData.icon, true)
                    visible: status === Image.Ready
                    transformOrigin: Item.Bottom
                    scale: ma.pressed ? 0.88 : (ma.containsMouse ? 1.32 : 1)
                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                    SequentialAnimation on y {
                        running: app.bouncing; loops: Animation.Infinite
                        NumberAnimation { to: -4; duration: 260; easing.type: Easing.OutQuad }
                        NumberAnimation { to: 5; duration: 260; easing.type: Easing.InQuad }
                        onRunningChanged: if (!running) img.y = 5
                    }
                }
                Rectangle {   // letter badge when the theme has no icon for this app
                    visible: img.status !== Image.Ready
                    width: 34; height: 34; radius: 10; y: 5
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Qt.hsla((modelData.name.charCodeAt(0) * 37 % 360) / 360, 0.45, 0.42, 1)
                    scale: img.scale; transformOrigin: Item.Bottom
                    Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: modelData.name.charAt(0).toUpperCase(); color: "white"
                        font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold }
                }
                Rectangle {   // running dot
                    width: app.focused ? 14 : 5; height: 4; radius: 2
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 1 }
                    color: app.focused ? Theme.accent : Theme.textDim
                    opacity: app.running ? 1 : 0
                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent; hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: {
                        if (containsMouse) { tipAnchor.x = app.mapToItem(w, app.width / 2, 0).x; w.hoverName = modelData.name; w.hovering = true; }
                        else w.hovering = false;
                    }
                    onClicked: m => {
                        if (m.button === Qt.RightButton) { w.menuApp = modelData; menuAnchor.x = app.mapToItem(w, app.width / 2, 0).x; menu.open = !menu.open; }
                        else if (m.button === Qt.MiddleButton) { modelData.entry.execute(); app.bouncing = true; bounceStop.restart(); }
                        else if (!w.activate(modelData)) { app.bouncing = true; bounceStop.restart(); }
                    }
                }
            }
        }

        Rectangle {   // + (opens picker / launcher)
            width: 34; height: 34; radius: 17; anchors.verticalCenter: parent.verticalCenter
            color: pm.containsMouse ? Theme.tileFillHover : Qt.rgba(1, 1, 1, 0.05)
            Behavior on color { ColorAnimation { duration: 140 } }
            Icon { anchors.centerIn: parent; name: "apps"; size: 20; color: Theme.textDim }
            MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.toggle() }
        }
    }

    // ---- hover tooltip: its own small window so it can extend past the dock ----
    PopupWindow {
        id: tip
        visible: w.hovering && !menu.open
        anchor.item: tipAnchor
        anchor.edges: Dock.popBelow ? Edges.Bottom : Edges.Top
        anchor.gravity: Dock.popBelow ? Edges.Bottom : Edges.Top
        anchor.adjustment: PopupAdjustment.Slide | PopupAdjustment.Flip
        color: "transparent"
        implicitWidth: Math.ceil((tipLbl.implicitWidth + 20) * Dock.uiScale)
        implicitHeight: Math.ceil(28 * Dock.uiScale)
        Rectangle {
            anchors.fill: parent; radius: height / 2
            color: Theme.popFill; border.width: 1; border.color: Theme.hairline
            Text { textFormat: Text.PlainText; id: tipLbl; anchors.centerIn: parent; text: w.hoverName; color: Theme.text
                font.family: Theme.font; font.pixelSize: 11 * Dock.uiScale }
        }
    }

    // ---- right-click menu (one shared popover, retargeted per app) ----
    Popover {
        id: menu
        target: menuAnchor
        panelWidth: 210
        panelHeight: 64 + (w.menuApp && w.menuApp.wins.length ? 40 : 0) + 80
        Column {
            anchors { fill: parent; margins: 10 }
            spacing: 2
            Text { textFormat: Text.PlainText; text: w.menuApp ? w.menuApp.name : ""; color: Theme.text; font.family: Theme.font; font.weight: Font.DemiBold
                font.pixelSize: 13; bottomPadding: 6; leftPadding: 4; elide: Text.ElideRight; width: parent.width }
            Repeater {
                model: w.menuApp ? [
                    { l: "New window", i: "open_in_new", a: "new" },
                    ...(w.menuApp.wins.length ? [{ l: "Close", i: "close", a: "close", bad: true }] : []),
                    { l: w.menuApp.pinned ? "Unpin from dock" : "Pin to dock", i: w.menuApp.pinned ? "keep_off" : "keep", a: "pin" },
                    { l: "Hide from list", i: "visibility_off", a: "hide" }
                ] : []
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width; height: 36; radius: 10
                    color: mm.containsMouse ? Theme.tileFillHover : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Row { x: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                        Icon { name: modelData.i; size: 18; color: modelData.bad ? Theme.bad : Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: modelData.l; color: modelData.bad ? Theme.bad : Theme.text; font.family: Theme.font; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter } }
                    MouseArea { id: mm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const a = w.menuApp; menu.open = false;
                            if (modelData.a === "new") a.entry.execute();
                            else if (modelData.a === "close") a.wins.forEach(t => t.close());
                            else if (modelData.a === "hide") w.setHidden(a.id, true);
                            else w.setPinned(a.id, !a.pinned);
                        } }
                }
            }
        }
    }

    // ---- app picker / launcher ----
    Popover {
        id: picker
        target: w
        panelWidth: 360
        panelHeight: 110 + Math.max(1, results.length) * 46
        readonly property var results: {
            const q = w.query.trim().toLowerCase();
            const all = DesktopEntries.applications.values.filter(e => !e.noDisplay && (w.showHidden || w.hidden.indexOf(e.id) < 0));
            const f = q ? all.filter(e => e.name.toLowerCase().indexOf(q) >= 0 || (e.genericName || "").toLowerCase().indexOf(q) >= 0) : all;
            return f.sort((a, b) => a.name.localeCompare(b.name)).slice(0, 8);
        }
        onOpenChanged: if (open) { w.query = ""; searchField.text = ""; searchField.forceActiveFocus(); }
        Column {
            anchors { fill: parent; margins: 12 }
            spacing: 6
            Rectangle {
                width: parent.width; height: 38; radius: 12; color: Theme.tileFill
                border.width: 1; border.color: searchField.activeFocus ? Theme.accent : Theme.hairline
                Behavior on border.color { ColorAnimation { duration: 150 } }
                Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 18; color: Theme.textDim }
                TextInput {
                    id: searchField
                    anchors { left: parent.left; leftMargin: 36; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13; clip: true
                    onTextChanged: w.query = text
                    onAccepted: { const r = picker.results[0]; if (r) { r.execute(); picker.open = false; } }
                    Text { visible: !searchField.text; text: "Search apps"; color: Theme.textDim; font: searchField.font; anchors.verticalCenter: parent.verticalCenter }
                }
            }
            Repeater {
                model: picker.results
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width; height: 42; radius: 10
                    color: rm.containsMouse ? Theme.tileFillHover : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Image { id: pi; x: 8; anchors.verticalCenter: parent.verticalCenter; width: 28; height: 28; sourceSize: Qt.size(112, 112)
                        source: Quickshell.iconPath(modelData.icon, true); smooth: true; mipmap: true; visible: status === Image.Ready }
                    Rectangle { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 28; height: 28; radius: 8; visible: pi.status !== Image.Ready
                        color: Qt.hsla((modelData.name.charCodeAt(0) * 37 % 360) / 360, 0.45, 0.42, 1)
                        Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: modelData.name.charAt(0).toUpperCase(); color: "white"; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Bold } }
                    readonly property bool isHidden: w.hidden.indexOf(modelData.id) >= 0
                    opacity: isHidden ? 0.5 : 1
                    Text { anchors { left: pi.right; leftMargin: 12; right: hideBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        elide: Text.ElideRight; text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                    IconButton {
                        id: hideBtn
                        width: 30; height: 30; radius: 15
                        anchors { right: pin.left; rightMargin: 2; verticalCenter: parent.verticalCenter }
                        icon: parent.isHidden ? "visibility" : "visibility_off"
                        onClicked: w.setHidden(modelData.id, !parent.isHidden)
                    }
                    IconButton {
                        id: pin
                        width: 30; height: 30; radius: 15
                        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        readonly property bool isPinned: w.pinned.indexOf(modelData.id) >= 0
                        icon: isPinned ? "keep_off" : "keep"; active: isPinned
                        onClicked: w.setPinned(modelData.id, !isPinned)
                    }
                    MouseArea { id: rm; anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: hideBtn.left }
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { modelData.execute(); picker.open = false; } }
                }
            }
            Rectangle {   // show / hide the hidden apps
                visible: w.hidden.length > 0
                width: parent.width; height: 30; radius: 10
                color: sh.containsMouse ? Theme.tileFillHover : "transparent"
                Row { anchors.centerIn: parent; spacing: 6
                    Icon { name: w.showHidden ? "visibility_off" : "visibility"; size: 16; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: w.showHidden ? "Stop showing hidden apps" : "Show " + w.hidden.length + " hidden"; color: Theme.textDim
                        font.family: Theme.font; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter } }
                MouseArea { id: sh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.showHidden = !w.showHidden }
            }
        }
    }
}
