pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// The "quick tiles": things that can sit on the dock OR in the quick settings panel.
// Placement rule (single source of truth): a tile is on the dock iff its widget id is in Dock.cfg.widgets,
// otherwise it appears in the quick panel. Moving = adding/removing that widget id.
// This singleton also owns the shared state (Focus, Night, Dark, VPN, Keep Awake, HQ VPN) and the actions, so the
// panel tiles and the dock tiles ("qtile:<id>" and the dedicated widgets) always agree.
Singleton {
    id: q
    readonly property string home: Quickshell.env("HOME")

    // id -> how it looks / which dock widget represents it
    readonly property var builtinCatalog: ({
        dnd:           { label: "Focus",         icon: "bedtime",              widget: "dnd" },
        night:         { label: "Night",         icon: "nightlight",           widget: "qtile:night" },
        dark:          { label: "Dark",          icon: "contrast",             widget: "qtile:dark" },
        vpn:           { label: "VPN",           icon: "vpn_key",              widget: "qtile:vpn" },
        awake:         { label: "Keep Awake",    icon: "center_focus_strong",  widget: "qtile:awake" },
        protonpass:    { label: "Proton Pass",   icon: "key",                  widget: "protonpass" },
        notifications: { label: "Notifications", icon: "notifications_unread", widget: "notifications" }
    })
    // built-in tiles plus the ones from your own quick-tiles.json (see "user tiles" below)
    readonly property var catalog: {
        const o = Object.assign({}, builtinCatalog);
        userTiles.forEach(t => { o[t.id] = { label: t.label, icon: t.icon, widget: t.widget }; });
        return o;
    }
    readonly property var ids: Object.keys(catalog)

    // User-defined shortcut tiles (widgetConfig.quicksettings.custom: [{id:"c_1", label, icon, cmd}]). They only ever
    // live in the quick panel, and a click just runs the user's own command (never built from remote text).
    readonly property var custom: {
        const c = (((Dock.cfg.widgetConfig || {}).quicksettings || {}).custom);
        return Array.isArray(c) ? c.filter(t => t && typeof t.id === "string" && /^c_[A-Za-z0-9_]+$/.test(t.id)) : [];
    }
    function customTile(id) { for (const t of custom) if (t.id === id) return t; return null; }
    function isCustom(id) { return customTile(id) !== null; }
    // label / icon / dock-widget for any tile id (catalog or custom); null for unknown ids
    function meta(id) {
        if (catalog[id]) return catalog[id];
        const t = customTile(id);
        return t ? { label: String(t.label || "Shortcut"), icon: String(t.icon || "bolt"), widget: "" } : null;
    }
    function known(id) { return meta(id) !== null; }

    function itemForWidget(widgetId) { for (const k of ids) if (catalog[k].widget === widgetId) return k; return ""; }
    function onDock(id) { return !!catalog[id] && (Dock.cfg.widgets || []).indexOf(catalog[id].widget) >= 0; }
    function panelHas(id) { return !onDock(id); }
    function label(id) { const m = meta(id); return m ? m.label : id; }
    function widgetLabel(widgetId) { const it = itemForWidget(widgetId); return it ? catalog[it].label + " (quick tile)" : widgetId; }

    function moveToPanel(id) { Dock.save({ widgets: (Dock.cfg.widgets || []).filter(x => x !== catalog[id].widget) }); }
    function moveToDock(id) {
        const w = (Dock.cfg.widgets || []).filter(x => x !== catalog[id].widget);
        // join the tools segment: just before the "|" that precedes the quick settings tile (or before it)
        let i = w.indexOf("quicksettings"); if (i < 0) i = w.length;
        if (i > 0 && w[i - 1] === "|") i -= 1;
        w.splice(i, 0, catalog[id].widget);
        Dock.save({ widgets: w });
    }

    // ---------------- user tiles ----------------
    // Tiles that belong to YOUR setup live in ~/.config/quickdock/quick-tiles.json ($XDG_CONFIG_HOME honoured), not in the
    // repo. Commands are argv arrays (never run through a shell); a leading "~/" is your home folder.
    //   [{ "id": "vpn2", "label": "Work VPN", "icon": "vpn_lock",
    //      "widget": "mywidget",                          // optional: dock widget id that represents this tile
    //      "toggle": ["~/bin/vpn", "work", "toggle"],     // run on click
    //      "state":  ["~/bin/vpn", "work", "status"],     // optional, polled: the tile is lit while the output equals "on"
    //      "on": "connected",                             // default "true"
    //      "place": { "class": "SomeApp", "w": 640, "h": 620 },   // optional: put that window next to the dock afterwards
    //      "hook": ["~/bin/app", "--focus-changed"] }]    // optional: run on every focus change, new window address appended
    readonly property string userTilesPath: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/quickdock/quick-tiles.json"
    property var userTiles: []
    property var userOn: ({})
    property var userBusy: ({})
    property var tileRefs: ({})
    property int tilePoll: 0
    function argv(a) {
        if (!Array.isArray(a) || a.length === 0 || a.length > 24) return null;
        const o = [];
        for (const x of a) { if (typeof x !== "string" || x.length === 0 || x.length > 400) return null; o.push(x.indexOf("~/") === 0 ? home + x.slice(1) : x); }
        return o;
    }
    function parseUserTiles(raw) {
        let j; try { j = JSON.parse(raw); } catch (e) { console.warn("quick-tiles.json:", e); return []; }
        if (!Array.isArray(j)) return [];
        const seen = {}, out = [];
        j.forEach(t => {
            if (!t || typeof t.id !== "string" || !/^[a-z][a-z0-9_]{0,23}$/.test(t.id) || builtinCatalog[t.id] || seen[t.id]) return;
            const toggle = argv(t.toggle); if (!toggle) return;
            seen[t.id] = true;
            const pc = t.place && typeof t.place["class"] === "string" && /^[A-Za-z0-9_.-]+$/.test(t.place["class"]);
            out.push({ id: t.id, label: String(t.label || t.id).slice(0, 40), icon: String(t.icon || "bolt").slice(0, 40),
                       widget: (typeof t.widget === "string" && /^[A-Za-z0-9_:-]+$/.test(t.widget)) ? t.widget : "",
                       toggle: toggle, state: argv(t.state), on: String(t.on || "true").toLowerCase(),
                       place: pc ? { cls: t.place["class"], w: Math.max(100, Math.min(4000, Number(t.place.w) || 640)), h: Math.max(100, Math.min(4000, Number(t.place.h) || 480)) } : null,
                       hook: argv(t.hook) });
        });
        return out;
    }
    FileView {
        path: q.userTilesPath
        printErrors: false              // the file is optional
        watchChanges: true
        onFileChanged: reload()
        onLoaded: q.userTiles = q.parseUserTiles(text())
        onLoadFailed: q.userTiles = []
    }
    // one helper object per user tile: polls its state, runs its (tracked) toggle
    Instantiator {
        model: q.userTiles
        delegate: QtObject {
            id: ut
            required property var modelData
            readonly property string tid: modelData.id
            property Process st: Process {
                command: ut.modelData.state || ["true"]
                stdout: StdioCollector { onStreamFinished: q.userOn = Object.assign({}, q.userOn, { [ut.tid]: text.trim().toLowerCase() === ut.modelData.on }) }
            }
            property Process act: Process {
                command: ut.modelData.toggle
                onRunningChanged: q.userBusy = Object.assign({}, q.userBusy, { [ut.tid]: running })
                stdout: StdioCollector { onStreamFinished: {
                    const t = text.trim().toLowerCase();
                    if (t) q.userOn = Object.assign({}, q.userOn, { [ut.tid]: t === ut.modelData.on });
                    q.later();
                } }
            }
            property Timer tick: Timer { interval: 8000; running: !!ut.modelData.state; repeat: true; triggeredOnStart: true
                onTriggered: if (!ut.act.running && !ut.st.running) ut.st.running = true }
            property Connections c: Connections { target: q
                function onTilePollChanged() { if (ut.modelData.state && !ut.act.running && !ut.st.running) ut.st.running = true; } }
            Component.onCompleted: { const r = Object.assign({}, q.tileRefs); r[ut.tid] = ut; q.tileRefs = r; }
            Component.onDestruction: { const r = Object.assign({}, q.tileRefs); if (r[ut.tid] === ut) delete r[ut.tid]; q.tileRefs = r; }
        }
    }
    function userTile(id) { for (const t of userTiles) if (t.id === id) return t; return null; }
    function busy(id) { return !!userBusy[id]; }

    // ---------------- shared state ----------------
    property bool dndOn: false
    property bool nightOn: false
    property bool darkOn: false
    property bool vpnOn: false
    readonly property bool awakeOn: awakeProc.running
    function isOn(id) {
        switch (id) {
        case "dnd": return dndOn; case "night": return nightOn; case "dark": return darkOn; case "vpn": return vpnOn;
        case "awake": return awakeOn;
        }
        return !!userOn[id];
    }
    function hasState(id) { if (["dnd", "night", "dark", "vpn", "awake"].indexOf(id) >= 0) return true; const t = userTile(id); return !!(t && t.state); }

    function poll() { pNight.running = true; pDark.running = true; pVpn.running = true; pDnd.running = true; tilePoll++; }
    Timer { interval: 8000; running: true; repeat: true; triggeredOnStart: true; onTriggered: q.poll() }
    Timer { id: repoll; interval: 1200; onTriggered: q.poll() }
    function later() { repoll.restart(); }

    Process { id: pNight; command: ["hyprctl", "hyprsunset", "temperature"]
        stdout: StdioCollector { onStreamFinished: { const t = parseInt(text); q.nightOn = !isNaN(t) && t < 5500; } } }
    Process { id: pDark; command: ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"]
        stdout: StdioCollector { onStreamFinished: q.darkOn = text.indexOf("dark") >= 0 } }
    Process { id: pVpn; command: ["sh", "-c", "tailscale status --json 2>/dev/null | jq -r .BackendState"]
        stdout: StdioCollector { onStreamFinished: q.vpnOn = text.trim() === "Running" } }
    Process { id: pDnd; command: ["dms", "ipc", "call", "notifications", "getDoNotDisturb"]
        stdout: StdioCollector { onStreamFinished: q.dndOn = text.trim() === "true" } }
    Process { id: awakeProc; command: ["systemd-inhibit", "--what=idle", "--who=quickdock", "--why=Keep awake", "sleep", "infinity"] }

    // ---------------- actions ----------------
    function run(cmd) { Quickshell.execDetached(cmd); }
    readonly property string protonScript: String(Qt.resolvedUrl("../scripts/protonpass-toggle")).replace("file://", "")
    readonly property string placer: String(Qt.resolvedUrl("../scripts/place-window.sh")).replace("file://", "")
    function toggle(id) {
        switch (id) {
        case "dnd": run(["dms", "ipc", "call", "notifications", "toggleDoNotDisturb"]); later(); break;
        case "night": run(["hyprctl", "hyprsunset", nightOn ? "identity" : "temperature"].concat(nightOn ? [] : ["4000"])); later(); break;
        case "dark": run(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", darkOn ? "default" : "prefer-dark"]); later(); break;
        case "vpn": run(["tailscale", vpnOn ? "down" : "up"]); later(); break;
        case "awake": awakeProc.running = !awakeProc.running; break;
        case "protonpass":
            run([protonScript]);
            run(["sh", "-c", "sleep 0.7; " + placer + " \"me\\.proton\\.Pass\" 881 760"]); break;
        case "notifications": run(["dms", "ipc", "call", "notifications", "toggle"]); break;
        default: {
            const u = userTile(id);
            if (u) {   // tile from quick-tiles.json
                const ref = tileRefs[id];
                if (u.state && ref) { if (!ref.act.running) ref.act.running = true; } else run(u.toggle);
                if (u.place) run(["sh", "-c", "sleep 0.7; " + placer + " \"" + u.place.cls + "\" " + u.place.w + " " + u.place.h]);
                break;
            }
            // custom tile: run the user's own shell command
            const t = customTile(id);
            if (t && typeof t.cmd === "string" && t.cmd.trim()) run(["sh", "-c", t.cmd]);
        }
        }
    }


    // The Proton Pass dropdown auto-hides when focus moves elsewhere; the hook lives here so it keeps working whether
    // its tile is on the dock or in the quick panel.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "activewindowv2") return;
            Quickshell.execDetached([q.protonScript, "--focus-changed", event.data]);
            q.userTiles.forEach(t => { if (t.hook) Quickshell.execDetached(t.hook.concat([event.data])); });
        }
    }
}
