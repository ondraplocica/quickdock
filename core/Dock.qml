pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Live view of config/dock.json (falls back to config/dock.default.json). Read `Dock.cfg`; change with `Dock.save({...})`.
// The file is watched, so hand edits and saves both flow back into `cfg`.
Singleton {
    id: dock
    property var cfg: ({ monitor: "", marginBottom: 14, accent: "", widgets: [], widgetConfig: {} })

    // Layout options (all optional in dock.json)
    readonly property string position: cfg.position === "top" ? "top" : "bottom"
    readonly property bool atTop: position === "top"
    readonly property real uiScale: Math.max(0.7, Math.min(1.6, cfg.scale || 1))
    // dropdownScale is independent; until you set it, dropdowns follow the bar scale
    readonly property real dropScale: Math.max(0.7, Math.min(1.8, cfg.dropdownScale !== undefined ? cfg.dropdownScale : uiScale))
    readonly property real edgeMargin: cfg.margin !== undefined ? cfg.margin : (cfg.marginBottom !== undefined ? cfg.marginBottom : 14)
    readonly property bool fullWidth: !!cfg.fullWidth

    readonly property string style: ["bar", "segments", "pills"].indexOf(cfg.style) >= 0 ? cfg.style : "bar"
    readonly property real barOpacity: cfg.opacity !== undefined ? Math.max(0.1, Math.min(1, cfg.opacity)) : 0.62
    // dropdown background opacity (0.6 - 1); the bar/segment fill has its own `opacity`
    readonly property real popOpacity: cfg.popoverOpacity !== undefined ? Math.max(0.6, Math.min(1, cfg.popoverOpacity)) : 0.985
    readonly property bool square: !!cfg.squareCorners
    readonly property int segSpacing: cfg.spacing !== undefined ? cfg.spacing : 8
    readonly property string dropdownSide: ["below", "above", "auto"].indexOf(cfg.dropdownSide) >= 0 ? cfg.dropdownSide : "below"
    // Dropdowns always open away from the dock: below a top dock, above a bottom dock (the only side with room)
    readonly property bool popBelow: atTop

    // Space between an icon and the dock's outer edge (bar/segments pad their tiles by one gap; pills have none),
    // so dropdowns can start a clear 8 px beyond the dock itself instead of overlapping it.
    readonly property int popGap: Math.round(style === "pills" ? 0 : 8 * uiScale) + 8

    signal closeAll()      // popups listen and close themselves
    signal openBuilder()   // shell.qml shows the bar-builder window
    signal openQsBuilder() // shell.qml shows the quick-settings builder window

    function save(patch) {
        const next = Object.assign({}, cfg, patch);
        cfg = next;
        userConfig = true;                // from now on config/dock.json is the source, not the shipped defaults
        file.setText(JSON.stringify(next, null, 2) + "\n");
    }
    // Merge into one widget's block of widgetConfig and save.
    function saveWidget(id, patch) {
        const wc = Object.assign({}, cfg.widgetConfig || {});
        wc[id] = Object.assign({}, wc[id] || {}, patch);
        save({ widgetConfig: wc });
    }

    // config/dock.json is YOUR config (git-ignored; created the first time you change a setting). Until it exists
    // the shipped defaults in config/dock.default.json are used.
    property bool userConfig: false
    FileView {
        id: defaults
        path: Qt.resolvedUrl("../config/dock.default.json")
        onLoaded: { if (!dock.userConfig) { try { dock.cfg = JSON.parse(text()); } catch (e) { console.warn("dock.default.json:", e); } } }
    }
    FileView {
        id: file
        path: Qt.resolvedUrl("../config/dock.json")
        printErrors: false              // it does not exist on a fresh install (the defaults are used then)
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { dock.cfg = JSON.parse(text()); dock.userConfig = true; } catch (e) { console.warn("dock.json:", e); } }
    }
}
