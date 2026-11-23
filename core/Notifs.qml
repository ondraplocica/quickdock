pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Passive notification history for the bell. DMS stays the notification daemon (popups, do-not-disturb, sounds);
// this only listens to the org.freedesktop.Notifications.Notify calls on the session bus (busctl monitor) and keeps
// the most recent ones in MEMORY ONLY (never written to disk). It cannot see notifications from before the dock
// started. All text is external data: show it as PlainText, never execute or interpolate it.
Singleton {
    id: n
    property var items: []            // newest first: { id, app, summary, body, icon, urgency, time }
    property int unread: 0            // total (PC + phone), what the bell badge shows
    property int unreadPhone: 0
    readonly property var pcItems: items.filter(x => x.src === "pc")
    readonly property var phoneItems: items.filter(x => x.src === "phone")
    readonly property int dedupeMs: 10 * 60 * 1000   // KDE Connect re-posts identical text; DMS only dedupes within 5 s
    property int seq: 0
    readonly property int maxItems: 40

    function clip(v, max) { return String(v === undefined || v === null ? "" : v).slice(0, max); }

    function ingest(line) {
        let m;
        try { m = JSON.parse(line); } catch (e) { return; }
        const d = m && m.payload && m.payload.data;
        if (!Array.isArray(d) || d.length < 7 || m.member !== "Notify") return;
        let app = clip(d[0], 60);
        const icon = clip(d[2], 300), summary = clip(d[3], 200), body = clip(d[4], 600);
        if (!summary && !body) return;
        // KDE Connect shows the PHONE's app name as the title and the text as the body
        const phone = app === "KDE Connect";
        if (phone && !body) return;                        // pings with no text
        const src = phone ? "phone" : "pc";
        if (phone) app = "Phone";
        const hints = d[6] || ({});
        const u = hints.urgency;
        const urgency = Number(u && typeof u === "object" ? u.data : u);
        const now = Date.now();
        // apps often re-send the same text; collapse repeats (PC: 3 s, phone: 10 min since the phone re-posts unchanged text)
        const win = phone ? dedupeMs : 3000;
        for (let i = 0; i < items.length; i++) {
            const x = items[i];
            if (x.src === src && x.app === app && x.summary === summary && x.body === body && now - x.time < win) return;
        }
        const it = { id: ++seq, src: src, app: app, summary: summary, body: body, icon: icon, urgency: isNaN(urgency) ? 1 : urgency, time: now };
        items = [it].concat(items).slice(0, maxItems);
        if (phone) unreadPhone = Math.min(99, unreadPhone + 1);
        unread = Math.min(99, unread + 1);
    }
    function dismiss(id) { items = items.filter(x => x.id !== id); }
    function clearAll() { items = []; unread = 0; unreadPhone = 0; }
    function clearSrc(src) { items = items.filter(x => x.src !== src); if (src === "phone") { unread = Math.max(0, unread - unreadPhone); unreadPhone = 0; } else unread = unreadPhone; }
    function markRead() { unread = 0; unreadPhone = 0; }
    function markReadSrc(src) { if (src === "phone") { unread = Math.max(0, unread - unreadPhone); unreadPhone = 0; } else unread = unreadPhone; }
    // test hook (no bus involved)
    function push(app, summary, body, icon, urgency) {   // app "KDE Connect" = phone
        ingest(JSON.stringify({ member: "Notify", payload: { data: [app, 0, icon || "", summary, body || "", [], { urgency: { type: "y", data: urgency === undefined ? 1 : urgency } }, -1] } }));
    }

    Process {
        id: mon
        running: true
        command: ["busctl", "--user", "monitor", "--json=short", "--match", "type='method_call',interface='org.freedesktop.Notifications',member='Notify'"]
        stdout: SplitParser { onRead: line => n.ingest(line) }
        onExited: restart.start()      // busctl exits if the bus restarts; come back
    }
    Timer { id: restart; interval: 5000; onTriggered: mon.running = true }
}
