import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import "core"

ShellRoot {
    id: root
    // Never hot-reload on file edits: tearing the dock down while one of its popups is mapped crashes
    // Hyprland 0.55.4. Restart explicitly (after `ipc call dock closeAll`) instead.
    settings.watchFiles: false
    readonly property var cfg: Dock.cfg            // live view of config/dock.json
    property var items: ({})                      // id -> loaded widget instance (for IPC)
    // Always run the StatusNotifier host/watcher, even when the `tray` widget isn't on the dock. Apps (and
    // scripts like quickshare-toggle) look tray icons up through org.kde.StatusNotifierWatcher, which
    // otherwise has no owner now that the DMS bar is off.
    readonly property int trayHost: SystemTray.items.values.length
    // Instantiate the quick-tile singleton at startup: it owns the shared tile state and the Quick Share / Proton Pass focus hooks
    readonly property int quickInit: Quick.ids.length
    // Start the notification history listener at startup so it collects even before the bell is clicked
    readonly property int notifInit: Notifs.items.length
    Binding { target: Theme; property: "accent"; value: root.cfg.accent || "#8ab4ff" }

    // "widgets" is a flat list: ids, "|" (segment break) and "@left" / "@center" / "@right" (start of a zone).
    // Compact layout: one centred dock, markers act like breaks. Sections layout: full-width bar with
    // left / centre / right zones. Only rebuilt when the list or layout really changes, so saving other
    // settings never tears down and recreates every widget.
    readonly property bool sections: cfg.layout === "sections"
    property var zones: ({ left: [], center: [], right: [] })   // zone -> array of segments (arrays of ids)
    property var segsAll: []                                     // all segments in order (compact layout)
    property string _key: ""
    readonly property real segGap: Dock.style === "bar" ? Theme.gap * 2 + 1 : Dock.segSpacing
    function rebuild() {
        const list = cfg.widgets || [];
        const key = JSON.stringify(list);
        if (key === _key) return;
        _key = key;
        const z = { left: [[]], center: [[]], right: [[]] };
        const all = [[]];
        const last = a => a[a.length - 1];
        let zone = "left";                                       // items before any marker
        list.forEach(id => {
            if (id === "@left" || id === "@center" || id === "@right") {
                zone = id.slice(1);
                if (last(z[zone]).length) z[zone].push([]);
                if (last(all).length) all.push([]);
            } else if (id === "|") {
                if (last(z[zone]).length) z[zone].push([]);
                if (last(all).length) all.push([]);
            } else { last(z[zone]).push(id); last(all).push(id); }
        });
        const clean = arr => arr.filter(g => g.length > 0);
        zones = { left: clean(z.left), center: clean(z.center), right: clean(z.right) };
        segsAll = clean(all);
    }
    onCfgChanged: rebuild()
    Component.onCompleted: rebuild()

    // One segment: optional background, divider, and its widgets.
    Component {
        id: segComp
        Item {
            id: seg
            required property var modelData      // array of widget ids
            required property int index
            width: segRow.implicitWidth + (Dock.style === "segments" ? 2 * Theme.gap : 0)
            height: Theme.tileHeight + 2 * Theme.gap

            Rectangle {   // segment background ("segments" style only)
                anchors.fill: parent
                visible: Dock.style === "segments"
                radius: Theme.dockRadius
                color: Theme.dockFill
                border.width: 1; border.color: Theme.hairline
            }
            Rectangle {   // divider between segments in "bar" style
                visible: Dock.style === "bar" && seg.index > 0
                width: 1; height: 28; color: Theme.hairlineHover
                x: -(root.segGap / 2) - 0.5
                anchors.verticalCenter: parent.verticalCenter
            }
            Row {
                id: segRow
                anchors.centerIn: parent
                spacing: Theme.gap
                Repeater {
                    model: seg.modelData
                    // Widget contract: widgets/<id>/Widget.qml (or ~/.config/quickdock/widgets/<id>/, see core/UserWidgets.qml), root type = Tile
                    delegate: Loader {
                        required property string modelData
                        source: UserWidgets.settled ? UserWidgets.source(modelData.split(":")[0]) : ""
                        onLoaded: {
                            item.instanceId = modelData;
                            item.config = (root.cfg.widgetConfig || {})[modelData] || ({});
                            root.items[modelData] = item;
                        }
                        onStatusChanged: if (status === Loader.Error) console.warn("widget failed:", modelData)
                    }
                }
            }
        }
    }

    // Builder windows. A Quickshell window that was closed once cannot be shown again, so each builder lives in a
    // LazyLoader: opening activates it (fresh window), closing destroys it (next open creates a new one).
    LazyLoader { id: barLoader; active: false
        Builder { visible: true; onVisibleChanged: if (!visible) barClose.restart() } }
    Timer { id: barClose; interval: 50; onTriggered: barLoader.active = false }
    Connections { target: Dock; function onOpenBuilder() { barLoader.active = true; } }
    LazyLoader { id: qsLoader; active: false
        QsBuilder { visible: true; onVisibleChanged: if (!visible) qsClose.restart() } }
    Timer { id: qsClose; interval: 50; onTriggered: qsLoader.active = false }
    Connections { target: Dock; function onOpenQsBuilder() { qsLoader.active = true; } }

    // quickshell -p ~/quickdock ipc call dock toggle weather   (handy for testing popovers)
    IpcHandler {
        target: "dock"
        function toggle(id: string): void {
            const it = root.items[id];
            if (it && it.toggle) it.toggle();
        }
        // open the interactive bar builder: ... ipc call dock builder
        function builder(): void { Dock.openBuilder(); }
        // open the quick-settings builder: ... ipc call dock qsbuilder
        function qsbuilder(): void { Dock.openQsBuilder(); }
        // close every popup (dropdowns, tooltips, menus) -- run this, wait ~1 s, THEN restart the dock
        function closeAll(): void { Dock.closeAll(); }
        // run a widget's own test/quick action: ... ipc call dock action quicksettings out
        function action(id: string, arg: string): void {
            const it = root.items[id];
            if (it && it.action) it.action(arg);
        }
        // open a widget's settings page (if it has one): ... ipc call dock settings quicksettings
        function settings(id: string): void {
            const it = root.items[id];
            if (it && it.openSettings) it.openSettings();
        }
    }

    Variants {
        model: Quickshell.screens   // windows are never rebuilt on config changes; `visible` selects the monitor
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: !root.cfg.monitor || modelData.name === root.cfg.monitor
            anchors.bottom: !Dock.atTop
            anchors.top: Dock.atTop
            anchors.left: root.sections          // sections layout stretches across the screen
            anchors.right: root.sections
            margins.left: root.sections && !Dock.fullWidth ? Dock.edgeMargin : 0
            margins.right: root.sections && !Dock.fullWidth ? Dock.edgeMargin : 0
            margins.bottom: Dock.atTop ? 0 : Dock.edgeMargin
            margins.top: Dock.atTop ? Dock.edgeMargin : 0
            // reserveSpace: true keeps windows from sitting under the dock (like a bar).
            // The layer-shell margin is added by the compositor, so the zone is just the height.
            exclusiveZone: root.cfg.reserveSpace ? implicitHeight : 0
            color: "transparent"

            readonly property real contentW: row.implicitWidth + (Dock.style === "bar" ? 2 * Theme.gap : 0)
            property real animW: contentW
            Behavior on animW { NumberAnimation { duration: Theme.medium; easing.type: Easing.OutCubic } }

            implicitWidth: (Dock.fullWidth || root.sections) ? modelData.width : Math.ceil(animW * Dock.uiScale)
            implicitHeight: Math.ceil((Theme.tileHeight + 2 * Theme.gap) * Dock.uiScale)
            WlrLayershell.namespace: "quickdock"
            WlrLayershell.layer: WlrLayer.Top

            // Everything is laid out at 1x inside `holder`, then scaled as one piece.
            Item {
                id: holder
                anchors.centerIn: parent
                width: (Dock.fullWidth || root.sections) ? win.width / Dock.uiScale : win.animW
                height: Theme.tileHeight + 2 * Theme.gap
                scale: Dock.uiScale

                Rectangle {
                    id: dock
                    anchors.fill: parent
                    // "bar" = one shared background; "segments"/"pills" draw their own backgrounds below
                    color: Dock.style === "bar" ? Theme.dockFill : "transparent"
                    radius: Dock.fullWidth && Dock.style === "bar" ? 0 : Theme.dockRadius
                    border.width: Dock.style === "bar" ? 1 : 0
                    border.color: Theme.hairline

                    Row {   // compact layout: everything in one centred row
                        id: row
                        anchors.centerIn: parent
                        spacing: root.segGap
                        Repeater { model: root.sections ? [] : root.segsAll; delegate: segComp }
                    }
                    // sections layout: left / centre / right zones
                    Row {
                        id: leftRow
                        anchors.left: parent.left
                        anchors.leftMargin: Dock.style === "bar" ? Theme.gap : 0
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: root.segGap
                        Repeater { model: root.sections ? root.zones.left : []; delegate: segComp }
                    }
                    Row {
                        id: centerRow
                        anchors.centerIn: parent
                        spacing: root.segGap
                        Repeater { model: root.sections ? root.zones.center : []; delegate: segComp }
                    }
                    Row {
                        id: rightRow
                        anchors.right: parent.right
                        anchors.rightMargin: Dock.style === "bar" ? Theme.gap : 0
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: root.segGap
                        Repeater { model: root.sections ? root.zones.right : []; delegate: segComp }
                    }
                }
            }
        }
    }
}
