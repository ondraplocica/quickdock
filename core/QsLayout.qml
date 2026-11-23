pragma Singleton
import QtQuick

// Shared layout logic for the quick-settings panel and its builder (core/QsBuilder.qml).
// Config lives in dock.json -> widgetConfig.quicksettings; every key is optional and the defaults reproduce the
// original fixed panel:
//   order:  module ids, top to bottom       default ["top","shortcuts","display","sound","mic","player"]
//   zones:  { top: [tile ids], conn: [...], shortcuts: [...] }
//             top      = first tile is the wide "Focus"-style card, the rest are square tiles (max 4 in total)
//             conn     = rows appended to the connectivity card (after the fixed Network + Bluetooth rows)
//             shortcuts= 4-column grid
//   custom: [{ id: "c_<n>", label, icon, cmd }]   user shortcut tiles (see Quick.qml)
//   hidden: hidden module hide-ids ("top","shortcuts","display","out","mic","player") and hidden tile ids (legacy edit mode)
// All functions are pure (they only read Dock.cfg / Quick), so a test harness can call them directly.
QtObject {
    id: qsl

    readonly property var defaultOrder: ["top", "shortcuts", "display", "sound", "mic", "player"]
    readonly property var defaultZones: ({
        top:       ["dnd", "night", "dark"],
        conn:      ["vpn"],
        shortcuts: ["awake", "notifications"] })
    readonly property var zoneKeys: ["top", "conn", "shortcuts"]
    readonly property var capacity: ({ top: 4, conn: 6, shortcuts: 24 })
    readonly property var zoneInfo: ({
        top:       { label: "Top tiles",    hint: "first = wide card, then squares (max 4)" },
        conn:      { label: "Connectivity", hint: "rows under Network and Bluetooth" },
        shortcuts: { label: "Shortcuts",    hint: "grid of 4 per row" } })
    // hid = the id used in the (legacy) `hidden` list
    readonly property var modules: ({
        top:       { label: "Connectivity & toggles", icon: "toggle_on",         hid: "top",       tiles: true,  desc: "" },
        shortcuts: { label: "Shortcuts",              icon: "apps",              hid: "shortcuts", tiles: true,  desc: "" },
        display:   { label: "Display",                icon: "brightness_medium", hid: "display",   tiles: false, desc: "Backlight slider (only on machines with a backlight)" },
        sound:     { label: "Sound",                  icon: "volume_up",         hid: "out",       tiles: false, desc: "Volume slider + output device picker" },
        mic:       { label: "Microphone",             icon: "mic",               hid: "mic",       tiles: false, desc: "Microphone slider + input device picker" },
        player:    { label: "Now Playing",            icon: "music_note",        hid: "player",    tiles: false, desc: "Shown while a media player is open" } })

    function cfg() { return ((Dock.cfg.widgetConfig || {}).quicksettings) || ({}); }
    function hiddenList(c) { return Array.isArray((c || cfg()).hidden) ? (c || cfg()).hidden.map(String) : []; }

    function normOrder(o) {
        const out = [];
        (Array.isArray(o) ? o : []).forEach(m => { if (modules[m] && out.indexOf(m) < 0) out.push(m); });
        defaultOrder.forEach(m => { if (out.indexOf(m) < 0) out.push(m); });
        return out;
    }
    // zones from config: unknown ids dropped, duplicates removed (first zone wins), capacity enforced;
    // a zone key that is absent falls back to its default, a present (even empty) array is respected
    function normZones(z) {
        const seen = {}, out = {};
        zoneKeys.forEach(k => {
            const src = (z && Array.isArray(z[k])) ? z[k] : defaultZones[k];
            out[k] = [];
            src.forEach(id => {
                if (typeof id === "string" && Quick.known(id) && !seen[id] && out[k].length < capacity[k]) { seen[id] = true; out[k].push(id); }
            });
        });
        return out;
    }
    // catalog tiles that are in no zone and not hidden (e.g. a tile that just came back from the dock) land in Shortcuts
    function withFallback(z, hidden) {
        const placed = {};
        zoneKeys.forEach(k => z[k].forEach(id => placed[id] = true));
        Quick.ids.forEach(id => { if (!placed[id] && hidden.indexOf(id) < 0) z.shortcuts.push(id); });
        return z;
    }

    // ---- what the panel shows right now ----
    function view() {
        const c = cfg(), hidden = hiddenList(c);
        const z = withFallback(normZones(c.zones), hidden);
        const vis = id => Quick.panelHas(id) && hidden.indexOf(id) < 0;
        const topWide = (z.top.length && vis(z.top[0])) ? z.top[0] : "";
        const top = z.top.filter(vis);
        return {
            order: normOrder(c.order),
            hiddenMods: normOrder(c.order).filter(m => hidden.indexOf(modules[m].hid) >= 0),
            conn: z.conn.filter(vis),
            shortcuts: z.shortcuts.filter(vis),
            topWide: topWide,
            topSquares: top.filter(id => id !== topWide).slice(0, 3)
        };
    }

    // ---- builder draft: { order, zones{top,conn,shortcuts}, docked{id:zone}, hiddenMods[], custom[] } ----
    function parse(c) {
        c = c || cfg();
        const hidden = hiddenList(c), order = normOrder(c.order), z = normZones(c.zones);
        const zones = { top: [], conn: [], shortcuts: [] }, docked = {};
        zoneKeys.forEach(k => z[k].forEach(id => {
            if (Quick.onDock(id)) docked[id] = k;              // lives on the bar: kept in its zone, shown read-only
            else if (hidden.indexOf(id) < 0) zones[k].push(id);   // hidden tiles count as "not placed" (shelf)
        }));
        const placed = {};
        zoneKeys.forEach(k => zones[k].forEach(id => placed[id] = true));
        // same fallback the panel applies, so the builder preview matches what is on screen
        Quick.ids.forEach(id => { if (!placed[id] && !docked[id] && hidden.indexOf(id) < 0 && !z.top.concat(z.conn, z.shortcuts).includes(id)) zones.shortcuts.push(id); });
        return { order: order, zones: zones, docked: docked,
                 hiddenMods: order.filter(m => hidden.indexOf(modules[m].hid) >= 0),
                 custom: Quick.custom.map(t => ({ id: t.id, label: String(t.label || ""), icon: String(t.icon || ""), cmd: String(t.cmd || "") })) };
    }
    // draft -> the object saved under widgetConfig.quicksettings
    function toConfig(d) {
        const placed = {}, zones = {};
        zoneKeys.forEach(k => d.zones[k].forEach(id => placed[id] = true));
        zoneKeys.forEach(k => {
            zones[k] = d.zones[k].slice();
            Object.keys(d.docked).forEach(id => { if (d.docked[id] === k) zones[k].push(id); });
        });
        const hidden = d.hiddenMods.map(m => modules[m].hid);
        Quick.ids.forEach(id => { if (!placed[id] && !d.docked[id]) hidden.push(id); });   // unplaced catalog tiles stay off the panel
        return { order: d.order.slice(), zones: zones, hidden: hidden,
                 custom: d.custom.map(t => ({ id: t.id, label: t.label, icon: t.icon, cmd: t.cmd })) };
    }
    function emptyDraft() { return { order: defaultOrder.slice(), zones: { top: [], conn: [], shortcuts: [] }, docked: {}, hiddenMods: [], custom: [] }; }
    function defaultDraft() {
        const d = emptyDraft();
        zoneKeys.forEach(k => defaultZones[k].forEach(id => { if (!Quick.onDock(id)) d.zones[k].push(id); else d.docked[id] = k; }));
        return d;
    }

    // ---- pure draft edits (return a new draft; callers assign it so bindings refresh) ----
    function cloneDraft(d) {
        return { order: d.order.slice(), docked: Object.assign({}, d.docked), hiddenMods: d.hiddenMods.slice(),
                 zones: { top: d.zones.top.slice(), conn: d.zones.conn.slice(), shortcuts: d.zones.shortcuts.slice() },
                 custom: d.custom.map(t => Object.assign({}, t)) };
    }
    function zoneOf(d, id) { for (const k of zoneKeys) if (d.zones[k].indexOf(id) >= 0) return k; return ""; }
    // move tile `id` to zone `zone` at index `idx` (index into the zone as it is BEFORE removing the tile);
    // returns the new draft, or null when the zone is full
    function placeTile(d, id, zone, idx) {
        const n = cloneDraft(d), TOKEN = "\u0000t";
        const old = zoneOf(n, id);
        const dest = n.zones[zone];
        if (old !== zone && dest.length >= capacity[zone]) return null;
        dest.splice(Math.max(0, Math.min(idx, dest.length)), 0, TOKEN);
        if (old) { const a = n.zones[old], i = a.indexOf(id); if (i >= 0) a.splice(i, 1); }
        dest[dest.indexOf(TOKEN)] = id;
        return n;
    }
    function removeTile(d, id) {
        const n = cloneDraft(d);
        zoneKeys.forEach(k => { const i = n.zones[k].indexOf(id); if (i >= 0) n.zones[k].splice(i, 1); });
        return n;
    }
    // move a module so that it ends up at position `idx` (index into the order as it is BEFORE removing it)
    function moveModule(d, mod, idx) {
        const n = cloneDraft(d), TOKEN = "\u0000m";
        n.order.splice(Math.max(0, Math.min(idx, n.order.length)), 0, TOKEN);
        n.order.splice(n.order.indexOf(mod), 1);
        n.order[n.order.indexOf(TOKEN)] = mod;
        return n;
    }
    function toggleModule(d, mod) {
        const n = cloneDraft(d), i = n.hiddenMods.indexOf(mod);
        if (i >= 0) n.hiddenMods.splice(i, 1); else n.hiddenMods.push(mod);
        return n;
    }
    function nextCustomId(d) {
        let n = 1; const used = {};
        d.custom.forEach(t => used[t.id] = true);
        Quick.custom.forEach(t => used[t.id] = true);
        while (used["c_" + n]) n++;
        return "c_" + n;
    }
}
