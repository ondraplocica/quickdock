import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"

// Next calendar event: "Standup · 12 min" chip (amber under warnMinutes, accent while it is running) and an
// agenda dropdown. Data comes from the clock widget's cal.py (iCal link in ~/.config/quickdock/calendar.json +
// local events in ~/.local/share/quickdock/events.json) -- nothing new to configure.
// Config (dock.json -> widgetConfig.nextevent): { "hideWhenEmpty": true, "warnMinutes": 15, "horizonDays": 7, "h12": false }
Tile {
    id: w
    readonly property var nc: (Dock.cfg.widgetConfig || {})[instanceId || "nextevent"] || config || ({})
    readonly property bool hideEmpty: nc.hideWhenEmpty !== false
    readonly property int warnMin: nc.warnMinutes !== undefined ? nc.warnMinutes : 15
    readonly property int horizon: Math.max(1, Math.min(31, nc.horizonDays || 7))
    readonly property bool h12: !!nc.h12
    readonly property var loc: Qt.locale(nc.locale || "en_US")
    readonly property string script: String(Qt.resolvedUrl("../clock/cal.py")).replace("file://", "")

    property var events: []                 // parsed: { title, loc, cal, allDay, s, e }
    property bool loaded: false
    property string calErr: ""
    property date now: new Date()

    // ---------- helpers ----------
    function p2(n) { return (n < 10 ? "0" : "") + n; }
    function iso(d) { return d.getFullYear() + "-" + p2(d.getMonth() + 1) + "-" + p2(d.getDate()); }
    function dayStart(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()); }
    function addDays(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n); }
    function parseT(str, allDay) {
        if (allDay) { const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(str); if (m) return new Date(+m[1], +m[2] - 1, +m[3]); }
        return new Date(str);
    }
    function clock(d) { return h12 ? d.toLocaleTimeString(loc, "h:mm AP") : p2(d.getHours()) + ":" + p2(d.getMinutes()); }
    function catColor(e) { return e.cal === "local" ? "#4cd68b" : (e.allDay ? "#8e7cff" : "#4c8dff"); }
    function trunc(s, n) { return s.length > n ? s.slice(0, n - 1) + "…" : s; }
    function dayLabel(d) {
        const diff = Math.round((dayStart(d) - dayStart(now)) / 86400000);
        return diff === 0 ? "Today" : (diff === 1 ? "Tomorrow" : d.toLocaleDateString(loc, "dddd d MMM"));
    }
    function relative(ms) {                                  // time until an event starts
        const m = Math.ceil(ms / 60000);
        if (m <= 0) return "now";
        if (m < 60) return m + " min";
        const h = Math.floor(m / 60), r = m % 60;
        if (h < 24) return h + " h" + (r ? " " + r + " m" : "");
        return Math.floor(h / 24) + " d";
    }

    function relShort(ms) {                                  // "35m", "1h 25m", "2d" -- compact, for the tile
        const m = Math.ceil(ms / 60000);
        if (m <= 0) return "now";
        if (m < 60) return m + "m";
        const h = Math.floor(m / 60), r = m % 60;
        if (h < 24) return h + "h" + (r ? " " + r + "m" : "");
        return Math.floor(h / 24) + "d";
    }

    // ---------- state derived from the event list ----------
    readonly property var upcoming: events.filter(e => e.e > now)                  // not over yet (running ones included)
    readonly property var nextEv: { const l = upcoming.filter(e => !e.allDay); return l.length ? l[0] : null; }
    readonly property real msLeft: nextEv ? nextEv.s - now : 0
    readonly property bool running: nextEv !== null && nextEv.s <= now
    readonly property bool soon: nextEv !== null && !running && msLeft < warnMin * 60000
    readonly property color tone: running ? Theme.accent : (soon ? Theme.warn : Theme.text)
    readonly property string chipText: nextEv
        ? trunc(nextEv.title, 22) + " · " + (running ? "now" : (msLeft < 86400000 ? relative(msLeft) : (dayLabel(nextEv.s) === "Tomorrow" ? "tomorrow " : nextEv.s.toLocaleDateString(loc, "ddd ")) + clock(nextEv.s)))
        : "No events"
    // tile pieces: bar colour (amber when soon, accent while running, else the calendar's colour), "14:20" and "in 1h 25m"
    readonly property color barColor: !nextEv ? Theme.textDim : (running ? Theme.accent : (soon ? Theme.warn : catColor(nextEv)))
    readonly property string subTime: !nextEv ? "" : (running ? "Now" : ((dayLabel(nextEv.s) === "Today" ? "" : (dayLabel(nextEv.s) === "Tomorrow" ? "Tomorrow " : nextEv.s.toLocaleDateString(loc, "ddd") + " ")) + clock(nextEv.s)))
    readonly property string subRel: !nextEv ? "" : (running ? "until " + clock(nextEv.e) : "in " + relShort(msLeft))
    readonly property bool shown: nextEv !== null || !hideEmpty || pop.open
    visible: shown
    implicitWidth: shown ? row.implicitWidth + 24 : 0
    active: soon || running
    function toggle() { if (!pop.open) reload(); pop.open = !pop.open; }
    onClicked: toggle()

    // flat agenda model: day headings + events, limited to ~9 rows
    readonly property var agenda: {
        const out = []; let last = "", n = 0;
        for (const e of upcoming) {
            if (n >= 9) break;
            const d = e.s < dayStart(now) ? dayStart(now) : e.s;
            const lab = dayLabel(d);
            if (lab !== last) { out.push({ head: lab }); last = lab; }
            out.push({ ev: e }); n++;
        }
        return out;
    }
    readonly property int agendaH: { let h = 0; for (const r of agenda) h += r.head ? 28 : 52; return h; }

    // ---------- data ----------
    function reload() {
        if (calp.running) return;
        const t = dayStart(new Date());
        calp.command = ["python3", "-I", script, "events", iso(t), iso(addDays(t, horizon + 1))];
        calp.running = true;
    }
    Timer { interval: 300000; running: true; repeat: true; triggeredOnStart: true; onTriggered: w.reload() }
    Timer { interval: 30000; running: true; repeat: true; onTriggered: w.now = new Date() }
    Process {
        id: calp
        stdout: StdioCollector { onStreamFinished: {
            try {
                const r = JSON.parse(text);
                if (!r.ok) { w.calErr = r.error || "error"; w.loaded = true; return; }
                w.events = r.events.map(e => ({ title: String(e.title || "(no title)"), loc: String(e.location || ""), cal: e.cal, allDay: !!e.allDay,
                                                s: w.parseT(e.start, !!e.allDay), e: w.parseT(e.end, !!e.allDay) }))
                                   .sort((a, b) => a.s - b.s);
                w.calErr = ""; w.loaded = true; w.now = new Date();
            } catch (err) { w.calErr = "parse"; w.loaded = true; } } }
    }

    Row { id: row; anchors.centerIn: parent; spacing: 9
        // calendar-day badge: the event's day number under two small red "binder rings"
        Item { visible: w.nextEv !== null; width: 28; height: 34; anchors.verticalCenter: parent.verticalCenter
            Row { anchors.horizontalCenter: parent.horizontalCenter; y: 1; spacing: 6
                Rectangle { width: 4; height: 4; radius: 2; color: "#ff453a" }
                Rectangle { width: 4; height: 4; radius: 2; color: "#ff453a" } }
            Text { anchors.horizontalCenter: parent.horizontalCenter; y: 7; text: w.nextEv ? w.nextEv.s.getDate() : ""
                color: Theme.text; font.family: Theme.font; font.pixelSize: 19; font.weight: Font.Bold } }
        Rectangle { visible: w.nextEv !== null; width: 3; height: 32; radius: 1.5; color: w.barColor; anchors.verticalCenter: parent.verticalCenter }
        Column { visible: w.nextEv !== null; anchors.verticalCenter: parent.verticalCenter; spacing: 1
            Text { text: w.nextEv ? w.trunc(w.nextEv.title, 26) : ""; textFormat: Text.PlainText
                color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Bold }
            Row { spacing: 5
                Text { text: w.subTime; textFormat: Text.PlainText; color: w.barColor; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium }
                Text { text: "·"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 }
                Text { text: w.subRel; textFormat: Text.PlainText; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 } } }
        // nothing coming up (only shown when hideWhenEmpty is off or the dropdown is open)
        Icon { visible: w.nextEv === null; anchors.verticalCenter: parent.verticalCenter; name: "event_available"; size: 22; color: Theme.textDim }
        Text { visible: w.nextEv === null; anchors.verticalCenter: parent.verticalCenter; text: "No events"
            color: Theme.textDim; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold } }

    Popover {
        id: pop
        target: w
        panelWidth: 330
        panelHeight: Math.max(150, 58 + (w.agenda.length ? w.agendaH + 8 : 90))
        Item {
            anchors.fill: parent
            Text { x: 16; y: 14; text: "Upcoming"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
            Text { anchors { right: parent.right; rightMargin: 16; baseline: parent.top; baselineOffset: 28 }
                text: w.nextEv ? (w.running ? "in progress" : "next in " + w.relative(w.msLeft)) : ""
                color: w.tone; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }

            Column { id: list; x: 10; y: 50; width: parent.width - 20; spacing: 0
                Repeater {
                    model: w.agenda
                    delegate: Item { required property var modelData
                        width: list.width; height: modelData.head ? 28 : 52
                        Text { visible: !!modelData.head; x: 6; anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                            text: modelData.head || ""; textFormat: Text.PlainText; color: Theme.textDim
                            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                        Item { visible: !!modelData.ev; anchors.fill: parent
                            readonly property var ev: modelData.ev
                            Text { x: 6; width: 54; anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText
                                text: parent.ev ? (parent.ev.allDay ? "All day" : w.clock(parent.ev.s)) : ""
                                color: parent.ev && parent.ev.s <= w.now && parent.ev.e > w.now ? Theme.accent : Theme.textDim
                                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                            Rectangle { x: 64; anchors.verticalCenter: parent.verticalCenter; width: 4; height: 34; radius: 2
                                color: parent.ev ? w.catColor(parent.ev) : "transparent" }
                            Column { x: 78; width: parent.width - 86; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText; text: parent.parent.ev ? parent.parent.ev.title : ""
                                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                                Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
                                    text: parent.parent.ev ? (parent.parent.ev.loc || (parent.parent.ev.allDay ? "" : w.clock(parent.parent.ev.s) + " – " + w.clock(parent.parent.ev.e))) : ""
                                    color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 } } } }
                }
            }

            Column { visible: w.agenda.length === 0; anchors.centerIn: parent; anchors.verticalCenterOffset: 14; spacing: 6; width: parent.width - 40
                Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "event_available"; size: 34; color: Theme.textDim }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; textFormat: Text.PlainText
                    text: !w.loaded ? "Loading…" : (w.calErr ? "Couldn't read your calendar (" + w.calErr + ")" : "Nothing in the next " + w.horizon + " days")
                    color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 }
                Text { visible: w.loaded && !w.calErr; width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                    text: "Link a calendar from the clock dropdown, or add a local event there."
                    color: Qt.rgba(1, 1, 1, 0.35); font.family: Theme.font; font.pixelSize: 11 } }
        }
    }
}
