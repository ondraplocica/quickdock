import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"

// Date + time tile (red weekday, big date | time), month calendar and agenda in the dropdown.
Tile {
    id: w
    implicitWidth: row.implicitWidth + 40
    property date now: new Date()
    readonly property var loc: Qt.locale(config.locale || "en_US")
    readonly property bool h12: config.hour12 === true
    function p2(n) { return (n < 10 ? "0" : "") + n; }
    function toggle() { pop.open = !pop.open; }
    onClicked: toggle()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: w.now = new Date() }

    // ---------- the tile ----------
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 22
        Column {   // date block
            id: dateCol
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Text { id: wdText; text: w.now.toLocaleDateString(w.loc, "dddd").toUpperCase(); color: "#ff453a"
                font.family: Theme.font; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.1 }
            Text { id: dtText; text: w.now.toLocaleDateString(w.loc, "MMM d"); color: Theme.text
                font.family: Theme.font; font.pixelSize: 18; font.weight: Font.Bold }
        }
        Column {   // time with a thin seconds bar underneath, centred as one group against the date block
            id: tblock
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            readonly property int sec: w.now.getSeconds()
            property real prog: (sec + 1) / 60                   // full bar at the end of each minute
            Behavior on prog { enabled: tblock.sec !== 0; NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }   // wraps to 0 without sweeping back
            Item {   // wrapper so the minute "roll" can move the text without fighting the layout
                width: tm.implicitWidth; height: tm.implicitHeight
                Text {
                    id: tm
                    text: w.h12 ? w.now.toLocaleTimeString(w.loc, "h:mm AP") : w.now.toLocaleTimeString(w.loc, "HH:mm")
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.Bold
                    onTextChanged: roll.restart()
                    SequentialAnimation { id: roll
                        ParallelAnimation {
                            NumberAnimation { target: tm; property: "opacity"; to: 0.25; duration: 80 }
                            NumberAnimation { target: tm; property: "y"; to: -4; duration: 80 } }
                        PropertyAction { target: tm; property: "y"; value: 4 }
                        ParallelAnimation {
                            NumberAnimation { target: tm; property: "opacity"; to: 1; duration: 170 }
                            NumberAnimation { target: tm; property: "y"; to: 0; duration: 220; easing.type: Easing.OutBack } } }
                }
            }
            Rectangle {   // seconds bar: track + fill, exactly as wide as the time
                width: tm.implicitWidth; height: 3; radius: 1.5; color: Qt.rgba(1, 1, 1, 0.12)
                Rectangle { width: parent.width * tblock.prog; height: parent.height; radius: 1.5; color: Theme.accent }
            }
        }
    }

    // ---------- calendar state ----------
    property int viewYear: now.getFullYear()
    property int viewMonth: now.getMonth()
    property date selected: new Date(now.getFullYear(), now.getMonth(), now.getDate())
    property var rawEvents: []
    property var evMap: ({})
    property bool hasFeed: false
    property string feedName: "Calendar"
    property string calState: "loading"     // loading | ok | error
    property string calMsg: ""
    property bool showCals: false
    property string newTime: ""
    property string newTitle: ""
    property bool addErr: false
    readonly property string calScript: String(Qt.resolvedUrl("cal.py")).replace("file://", "")
    readonly property var hiddenCals: ((Dock.cfg.widgetConfig || {}).clock || {}).hiddenCals || []
    function calHidden(c) { return hiddenCals.indexOf(c) >= 0; }
    function toggleCal(c) { const h = hiddenCals.slice(); const i = h.indexOf(c); if (i >= 0) h.splice(i, 1); else h.push(c); Dock.saveWidget("clock", { hiddenCals: h }); }
    onHiddenCalsChanged: rebuildMap()
    Connections { target: Dock; function onCloseAll() { w.showCals = false; } }

    function key(d) { return d.getFullYear() + "-" + p2(d.getMonth() + 1) + "-" + p2(d.getDate()); }
    function parseD(s) { return s.length === 10 ? new Date(+s.slice(0, 4), +s.slice(5, 7) - 1, +s.slice(8, 10)) : new Date(s); }
    function gridStart() { const first = new Date(viewYear, viewMonth, 1); return new Date(viewYear, viewMonth, 1 - ((first.getDay() + 6) % 7)); }
    function dayAt(i) { const s = gridStart(); return new Date(s.getFullYear(), s.getMonth(), s.getDate() + i); }
    function iso(d) { return d.getFullYear() + "-" + p2(d.getMonth() + 1) + "-" + p2(d.getDate()); }
    function reload() { calp.command = ["python3", "-I", calScript, "events", iso(gridStart()), iso(dayAt(42))]; calp.running = true; }
    function shiftMonth(delta) { const d = new Date(viewYear, viewMonth + delta, 1); viewYear = d.getFullYear(); viewMonth = d.getMonth(); reload(); }
    function goToday() { viewYear = now.getFullYear(); viewMonth = now.getMonth(); selected = new Date(now.getFullYear(), now.getMonth(), now.getDate()); reload(); }
    function sameDay(a, b) { return key(a) === key(b); }
    function dayEvents(d) { return evMap[key(d)] || []; }
    function catColor(e) { return e.cal === "local" ? "#4cd68b" : (e.allDay ? "#8e7cff" : "#4c8dff"); }
    function timeLabel(e) {
        if (e.allDay) return "All day";
        const s = new Date(e.start);
        return w.h12 ? s.toLocaleTimeString(w.loc, "h:mm AP") : p2(s.getHours()) + ":" + p2(s.getMinutes());
    }
    function isPast(e) { return !e.allDay && e.end && new Date(e.end) < now; }
    function subtitle(e) { return e.location || (e.cal === "local" ? "Local" : w.feedName); }
    function rebuildMap() {
        const m = {};
        rawEvents.forEach(e => {
            if (calHidden(e.cal)) return;
            const s = parseD(e.start); const en = e.end ? parseD(e.end) : s;
            const last = e.allDay ? new Date(en.getFullYear(), en.getMonth(), en.getDate() - 1)
                                  : new Date(en.getFullYear(), en.getMonth(), en.getDate() - (en.getHours() === 0 && en.getMinutes() === 0 && en > s ? 1 : 0));
            for (let d = new Date(s.getFullYear(), s.getMonth(), s.getDate()); d <= last && d - s < 40 * 86400000; d = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1)) {
                const k = key(d); (m[k] = m[k] || []).push(e);
            }
        });
        Object.keys(m).forEach(k => m[k].sort((a, b) => (b.allDay ? 1 : 0) - (a.allDay ? 1 : 0) || a.start.localeCompare(b.start)));
        evMap = m;
    }
    readonly property var legend: {
        const seen = { ev: false, all: false, loc: false };
        rawEvents.forEach(e => { if (calHidden(e.cal)) return; if (e.cal === "local") seen.loc = true; else if (e.allDay) seen.all = true; else seen.ev = true; });
        return [ seen.ev ? { l: "Events", c: "#4c8dff" } : null, seen.all ? { l: "All day", c: "#8e7cff" } : null, seen.loc ? { l: "Local", c: "#4cd68b" } : null ].filter(x => x);
    }
    function defaultTime() { const t = new Date(now.getTime() + 15 * 60000); return p2(t.getHours()) + ":" + p2(Math.ceil(t.getMinutes() / 5) % 12 * 5); }
    function submitNew() {
        const m = /^(\d{1,2}):(\d{2})$/.exec(newTime.trim()); const t = newTitle.trim();
        if (!m || !t || +m[1] > 23 || +m[2] > 59) { addErr = true; errTimer.restart(); return; }
        addp.command = ["python3", "-I", calScript, "add", key(selected) + "T" + p2(+m[1]) + ":" + m[2], t];
        addp.running = true; newTitle = "";
    }
    Timer { id: errTimer; interval: 900; onTriggered: w.addErr = false }
    Process {
        id: calp
        stdout: StdioCollector { onStreamFinished: {
            try {
                const r = JSON.parse(text);
                if (!r.ok) { w.calState = "error"; w.calMsg = r.error; return; }
                w.rawEvents = r.events; w.hasFeed = !!r.hasFeed; w.feedName = r.feedName || "Calendar";
                w.rebuildMap(); w.calState = "ok";
            } catch (e) { w.calState = "error"; w.calMsg = "parse"; }
        } }
    }
    Process { id: addp; stdout: StdioCollector { onStreamFinished: w.reload() } }
    Process { id: delp; stdout: StdioCollector { onStreamFinished: w.reload() } }
    Process { id: useClip; command: ["python3", "-I", w.calScript, "use-clipboard"]
        stdout: StdioCollector { onStreamFinished: { try { const r = JSON.parse(text); if (r.ok) { w.showCals = false; w.reload(); } else w.calMsg = r.error; } catch (e) { } } } }

    // world clocks
    readonly property var zones: (config.zones && config.zones.length) ? config.zones : [{ n: "UTC", z: "UTC" }]
    property var zoneTimes: []
    Timer { interval: 30000; running: pop.open; repeat: true; triggeredOnStart: true; onTriggered: zp.running = true }
    Process {
        id: zp
        command: ["sh", "-c", "for z in " + w.zones.map(x => x.z).join(" ") + "; do TZ=$z date '+%H:%M'; done"]
        stdout: StdioCollector { onStreamFinished: w.zoneTimes = text.trim().split("\n") }
    }

    Popover {
        id: pop
        target: w
        panelWidth: 920
        panelHeight: 584
        onOpenChanged: if (open) { w.showCals = false; w.newTime = w.defaultTime(); w.goToday(); }

        // ======================= left: month =======================
        Item {
            id: left
            x: 24; y: 22; width: 568; height: parent.height - 44

            Row {   // header
                id: head
                width: parent.width; height: 40
                Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 300
                    text: new Date(w.viewYear, w.viewMonth, 1).toLocaleDateString(w.loc, "MMMM, yyyy")
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 26; font.weight: Font.Bold; elide: Text.ElideRight }
                Row { anchors.verticalCenter: parent.verticalCenter; spacing: 10; layoutDirection: Qt.LeftToRight
                    Rectangle { height: 34; width: cl.implicitWidth + 28; radius: 17; color: w.showCals ? Theme.accent : Qt.rgba(1, 1, 1, 0.09)
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Text { id: cl; anchors.centerIn: parent; text: "Calendars"; color: w.showCals ? "#101218" : Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: w.showCals = !w.showCals } }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Today"; color: Theme.accent; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: w.goToday() } }
                    IconButton { width: 32; height: 32; radius: 16; icon: "chevron_left"; onClicked: w.shiftMonth(-1) }
                    IconButton { width: 32; height: 32; radius: 16; icon: "chevron_right"; onClicked: w.shiftMonth(1) }
                    IconButton { width: 32; height: 32; radius: 16; icon: "close"; onClicked: pop.open = false }
                }
            }
            Row {   // legend
                id: legendRow
                y: head.height + 8; height: 18; spacing: 16
                Repeater { model: w.legend
                    delegate: Row { required property var modelData; spacing: 6
                        Rectangle { width: 8; height: 8; radius: 4; color: modelData.c; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: modelData.l; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter } }
                }
            }
            Row {   // weekday pills
                id: wk
                y: legendRow.y + 28; spacing: 6
                Repeater { model: ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
                    delegate: Rectangle { required property string modelData; required property int index
                        readonly property bool isNow: ((w.now.getDay() + 6) % 7) === index
                        width: 76; height: 26; radius: 13; color: isNow ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.05)
                        Text { anchors.centerIn: parent; text: modelData; color: isNow ? Theme.text : Theme.textDim
                            font.family: Theme.font; font.pixelSize: 11; font.weight: isNow ? Font.Bold : Font.Medium; font.letterSpacing: 0.6 } }
                }
            }
            Grid {   // 6 weeks of rounded day tiles
                y: wk.y + 34; columns: 7; spacing: 6
                Repeater {
                    model: 42
                    delegate: Item {
                        id: cell
                        required property int index
                        readonly property date day: w.dayAt(index)
                        readonly property bool inMonth: day.getMonth() === w.viewMonth
                        readonly property bool isToday: w.sameDay(day, w.now)
                        readonly property bool isSel: w.sameDay(day, w.selected)
                        readonly property var evs: w.dayEvents(day)
                        readonly property bool has: evs.length > 0
                        width: 76; height: 64
                        scale: inMonth && cm.containsMouse ? 1.04 : 1
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                        Rectangle { anchors.fill: parent; radius: Theme.square ? 8 : 14; visible: cell.inMonth
                            color: cm.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.05)
                            border.width: cell.isSel ? 2 : (cell.isToday ? 1 : 0); border.color: Theme.accent
                            Behavior on color { ColorAnimation { duration: 120 } } }
                        Rectangle {   // event icon tile
                            visible: cell.inMonth && cell.has
                            width: 26; height: 26; radius: 8; y: 9
                            x: cell.evs.length > 1 ? 12 : (parent.width - width) / 2
                            color: cell.has ? w.catColor(cell.evs[0]) : "transparent"
                            Icon { anchors.centerIn: parent; name: "event"; size: 16; color: "white" }
                        }
                        Rectangle {   // +N badge
                            visible: cell.inMonth && cell.evs.length > 1
                            x: 44; y: 13; height: 18; width: bt.implicitWidth + 12; radius: 9; color: Qt.rgba(1, 1, 1, 0.14)
                            Text { id: bt; anchors.centerIn: parent; text: "+" + (cell.evs.length - 1); color: Theme.text; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold }
                        }
                        Rectangle {   // category dot, top right
                            visible: cell.inMonth && cell.has
                            width: 7; height: 7; radius: 3.5; x: parent.width - 14; y: 8
                            color: cell.has ? w.catColor(cell.evs[cell.evs.length - 1]) : "transparent"
                        }
                        Text { visible: cell.inMonth; anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 8 }
                            text: cell.day.getDate()
                            color: cell.isSel ? Theme.accent : (cell.has || cell.isToday ? Theme.text : Theme.textDim)
                            font.family: Theme.font; font.pixelSize: 14; font.weight: (cell.has || cell.isToday || cell.isSel) ? Font.Bold : Font.Medium }
                        MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; enabled: cell.inMonth; cursorShape: Qt.PointingHandCursor
                            onClicked: { w.selected = cell.day; w.newTime = w.sameDay(cell.day, w.now) ? w.defaultTime() : "09:00"; } }
                    }
                }
            }

            // ---- Calendars switcher ----
            Rectangle {
                visible: opacity > 0; opacity: w.showCals ? 1 : 0; z: 20
                x: parent.width - width; y: head.height + 4; width: 300; height: calCol.implicitHeight + 28; radius: 16
                color: Qt.rgba(0.09, 0.09, 0.11, 0.98); border.width: 1; border.color: Theme.hairlineHover
                Behavior on opacity { NumberAnimation { duration: 140 } }
                Column { id: calCol; x: 14; y: 14; width: parent.width - 28; spacing: 8
                    Text { text: "Calendars"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                    Repeater {
                        model: [ { id: "feed", name: w.hasFeed ? w.feedName : "No calendar linked", c: "#4c8dff", off: !w.hasFeed }, { id: "local", name: "Local events", c: "#4cd68b", off: false } ]
                        delegate: Rectangle { required property var modelData
                            width: calCol.width; height: 38; radius: 10; color: Qt.rgba(1, 1, 1, 0.05); opacity: modelData.off ? 0.45 : 1
                            Row { x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                                Rectangle { width: 10; height: 10; radius: 5; color: modelData.c; anchors.verticalCenter: parent.verticalCenter }
                                Text { textFormat: Text.PlainText; text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter } }
                            Rectangle { anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                width: 38; height: 22; radius: 11; color: !w.calHidden(modelData.id) && !modelData.off ? Theme.accent : Qt.rgba(1, 1, 1, 0.15)
                                Behavior on color { ColorAnimation { duration: 140 } }
                                Rectangle { width: 16; height: 16; radius: 8; y: 3; color: "white"; x: !w.calHidden(modelData.id) && !modelData.off ? 19 : 3
                                    Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutBack } } }
                                MouseArea { anchors.fill: parent; enabled: !modelData.off; cursorShape: Qt.PointingHandCursor; onClicked: w.toggleCal(modelData.id) } }
                        }
                    }
                    Text { visible: !w.hasFeed; width: parent.width; wrapMode: Text.WordWrap; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11
                        text: "To see Google Calendar events: open its settings, pick your calendar and copy “Secret address in iCal format”, then use the button below." }
                    Row { spacing: 8
                        Rectangle { height: 32; width: 168; radius: 16; color: Theme.accent
                            Text { anchors.centerIn: parent; text: w.hasFeed ? "Replace link from clipboard" : "Use link from clipboard"; color: "#101218"; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: useClip.running = true } }
                        Rectangle { height: 32; width: 90; radius: 16; color: Qt.rgba(1, 1, 1, 0.09)
                            Text { anchors.centerIn: parent; text: "Open settings"; color: Theme.text; font.family: Theme.font; font.pixelSize: 11 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["xdg-open", "https://calendar.google.com/calendar/u/0/r/settings"]) } }
                    }
                    Text { visible: w.calMsg === "not-ical" || w.calMsg === "no-clipboard"; color: Theme.bad; font.family: Theme.font; font.pixelSize: 11
                        text: w.calMsg === "not-ical" ? "That doesn't look like an https calendar link (.ics)." : "Nothing to read from the clipboard." }
                }
            }
        }

        // ======================= right: agenda =======================
        Rectangle {
            id: right
            x: 24 + 568 + 20; y: 22; width: parent.width - x - 24; height: parent.height - 44
            radius: Theme.square ? 10 : 20; color: Qt.rgba(1, 1, 1, 0.045)

            Column {
                x: 18; y: 16; width: parent.width - 36; spacing: 4
                Row { width: parent.width
                    Text { width: parent.width - 80; text: w.sameDay(w.selected, w.now) ? "Today" : w.selected.toLocaleDateString(w.loc, "ddd, MMM d")
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.Bold }
                    Text { width: 80; horizontalAlignment: Text.AlignRight; anchors.baseline: undefined
                        text: w.dayEvents(w.selected).length + (w.dayEvents(w.selected).length === 1 ? " event" : " events"); color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                }
                Text { width: parent.width; elide: Text.ElideRight; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11
                    text: w.zones.map((z, i) => z.n + " " + (w.zoneTimes[i] || "--:--")).join("   ·   ") }
            }

            Flickable {
                x: 12; y: 70; width: parent.width - 24; height: parent.height - 70 - 70
                contentHeight: agenda.height; clip: true; boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: agenda
                    width: parent.width; spacing: 6
                    Text { visible: w.dayEvents(w.selected).length === 0; topPadding: 14; width: parent.width; horizontalAlignment: Text.AlignHCenter
                        text: "Nothing planned"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 }
                    Rectangle {   // no feed linked: a gentle nudge
                        visible: !w.hasFeed && w.calState === "ok"; width: parent.width; height: 54; radius: 12; color: Qt.rgba(1, 1, 1, 0.05)
                        Text { x: 12; width: parent.width - 100; anchors.verticalCenter: parent.verticalCenter; wrapMode: Text.WordWrap; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11
                            text: "Show your Google Calendar here by linking its iCal address." }
                        Rectangle { anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } height: 28; width: 66; radius: 14; color: Theme.accent
                            Text { anchors.centerIn: parent; text: "Link"; color: "#101218"; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: w.showCals = true } }
                    }
                    Repeater {
                        model: w.dayEvents(w.selected)
                        delegate: Item {
                            id: er
                            required property var modelData
                            width: agenda.width; height: 50
                            opacity: w.isPast(modelData) ? 0.5 : 1
                            Text { x: 2; width: 62; anchors.verticalCenter: parent.verticalCenter; text: w.timeLabel(er.modelData)
                                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                            Rectangle { x: 70; anchors.verticalCenter: parent.verticalCenter; width: 32; height: 32; radius: 9; color: w.catColor(er.modelData)
                                Icon { anchors.centerIn: parent; name: er.modelData.cal === "local" ? "edit_calendar" : "event"; size: 18; color: "white" } }
                            Column { x: 112; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 112 - (er.modelData.cal === "local" ? 30 : 0)
                                Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: er.modelData.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                                Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: w.subtitle(er.modelData); color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 } }
                            Rectangle { visible: er.modelData.cal === "local" && erm.containsMouse; anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                width: 24; height: 24; radius: 12; color: Qt.rgba(1, 1, 1, 0.1)
                                Icon { anchors.centerIn: parent; name: "delete"; size: 15; color: Theme.textDim }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: { delp.command = ["python3", "-I", w.calScript, "remove", er.modelData.id]; delp.running = true; } } }
                            MouseArea { id: erm; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                        }
                    }
                }
            }

            Rectangle {   // quick add
                x: 12; y: parent.height - 58; width: parent.width - 24; height: 46; radius: 14; color: Qt.rgba(1, 1, 1, 0.07)
                border.width: w.addErr ? 1 : 0; border.color: Theme.bad
                Rectangle { x: 6; anchors.verticalCenter: parent.verticalCenter; width: 92; height: 34; radius: 10; color: Qt.rgba(1, 1, 1, 0.08)
                    TextInput { id: tf; anchors { left: parent.left; leftMargin: 10; right: tIc.left; verticalCenter: parent.verticalCenter }
                        text: w.newTime; onTextChanged: w.newTime = text; maximumLength: 5; selectByMouse: true
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                    Icon { id: tIc; anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } name: "schedule"; size: 16; color: Theme.textDim } }
                TextInput { id: nf
                    anchors { left: parent.left; leftMargin: 112; right: addBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    text: w.newTitle; onTextChanged: w.newTitle = text; clip: true; selectByMouse: true
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                    onAccepted: w.submitNew()
                    Text { visible: !nf.text; text: w.sameDay(w.selected, w.now) ? "New event today" : "New event on " + w.selected.toLocaleDateString(w.loc, "MMM d")
                        color: Theme.textDim; font: nf.font; anchors.verticalCenter: parent.verticalCenter } }
                Rectangle { id: addBtn; anchors { right: parent.right; rightMargin: 7; verticalCenter: parent.verticalCenter }
                    width: 32; height: 32; radius: 16; color: w.newTitle.trim() ? Theme.accent : Qt.rgba(1, 1, 1, 0.12)
                    Behavior on color { ColorAnimation { duration: 140 } }
                    scale: ab.pressed ? 0.9 : 1
                    Icon { anchors.centerIn: parent; name: "add"; size: 20; color: w.newTitle.trim() ? "#101218" : Theme.text }
                    MouseArea { id: ab; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: w.submitNew() } }
            }
        }
    }
}
