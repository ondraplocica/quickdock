import QtQuick
import Quickshell.Io
import "../../core"

// Home Assistant: health card + pinned entities (rename, unpin, controls) + a searchable "pin more" picker.
// Config (dock.json -> widgetConfig.home): { "pinned": ["light.x", ...], "names": { "light.x": "Desk lamp" } }
Tile {
    id: w
    implicitWidth: row.implicitWidth + 24
    readonly property var homeCfg: (Dock.cfg.widgetConfig || {}).home || ({})
    readonly property var pinned: homeCfg.pinned || []
    readonly property var names: homeCfg.names || ({})
    readonly property string script: String(Qt.resolvedUrl("ha.py")).replace("file://", "")
    property var ents: []
    property string state: "loading"       // loading | ok | no-config | error
    readonly property var toggles: ents.filter(e => isToggle(e))
    readonly property int onCount: toggles.filter(e => e.state === "on").length
    property string mode: "list"           // list | pick
    property string renamingId: ""
    active: false
    // Home Assistant health (separate, slower poll: /api/states is large)
    property var st: null
    property string stState: "loading"       // loading | ok | down | no-config
    readonly property color dot: stState === "ok" ? (st && st.unavailable > 0 ? Theme.warn : Theme.good) : (stState === "loading" ? Theme.textDim : Theme.bad)

    // ---- entity helpers ----
    readonly property var toggleDomains: ["light", "switch", "fan", "input_boolean", "automation"]
    readonly property var runDomains: ["scene", "script", "button"]
    function isToggle(e) { return toggleDomains.indexOf(e.domain) >= 0; }
    function isRun(e) { return runDomains.indexOf(e.domain) >= 0; }
    function displayName(e) { return (names[e.id] || "").trim() || e.name; }
    function iconFor(e, on) {
        switch (e.domain) {
        case "light": return on ? "lightbulb" : "light_off";
        case "switch": case "input_boolean": return on ? "toggle_on" : "toggle_off";
        case "fan": return "mode_fan";
        case "cover": return "blinds";
        case "climate": return "thermostat";
        case "scene": return "palette";
        case "script": case "button": return "play_circle";
        case "automation": return "automation";
        case "binary_sensor": return on ? "radio_button_checked" : "radio_button_unchecked";
        }
        switch (e.deviceClass) {
        case "temperature": return "device_thermostat";
        case "humidity": return "water_drop";
        case "battery": return "battery_full";
        case "power": case "energy": return "bolt";
        }
        return "sensors";
    }
    function valueText(e) {
        if (e.domain === "climate") return (e.temp !== null && e.temp !== undefined ? Math.round(e.temp * 10) / 10 + "°  " : "") + e.state;
        if (e.domain === "cover") return e.state;
        const v = parseFloat(e.state);
        return (isNaN(v) ? e.state : (Math.round(v * 100) / 100)) + (e.unit ? " " + e.unit : "");
    }
    function rowHeight(e) { return (e.dimmable && e.state === "on" && e.brightness !== null) ? 66 : 46; }
    function saveHome(patch) { Dock.saveWidget("home", patch); }
    function rename(id, text) {
        const n = Object.assign({}, names); const t = text.trim();
        if (t) n[id] = t; else delete n[id];
        saveHome({ names: n }); renamingId = "";
    }
    function unpin(id) { const n = Object.assign({}, names); delete n[id]; saveHome({ pinned: pinned.filter(x => x !== id), names: n }); }
    function pin(id) { if (pinned.indexOf(id) < 0) saveHome({ pinned: pinned.concat([id]) }); }
    onPinnedChanged: Qt.callLater(refresh)

    function toggle() { pop.open = !pop.open; if (pop.open) { mode = "list"; renamingId = ""; refresh(); stp.running = true; } }
    function openSettings() { mode = "pick"; pop.open = true; runSearch(); }      // `ipc call dock settings home` opens the picker
    onClicked: toggle()
    Connections { target: Dock; function onCloseAll() { w.renamingId = ""; } }
    function refresh() {
        if (!pinned.length) { ents = []; if (state === "loading") state = "ok"; return; }
        lister.running = true;
    }
    function call(domain, service, id, data) {
        actor.command = ["python3", "-I", script, "call", domain, service, id].concat(data ? [JSON.stringify(data)] : []);
        actor.running = true;
    }
    function toggleEntity(e) {
        const on = e.state === "on";
        if (isToggle(e)) call(e.domain, on ? "turn_off" : "turn_on", e.id);
    }
    function runEntity(e) { call(e.domain, e.domain === "button" ? "press" : "turn_on", e.id); }

    Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: w.refresh() }
    Timer { interval: 5000; running: pop.open && w.mode === "list"; repeat: true; onTriggered: w.refresh() }
    Process {
        id: lister
        command: ["python3", "-I", w.script, "states"].concat(w.pinned)
        stdout: StdioCollector { onStreamFinished: {
            try {
                const r = JSON.parse(text);
                if (r.ok) { w.ents = r.entities; w.state = "ok"; } else w.state = r.error === "no-config" ? "no-config" : "error";
            } catch (e) { w.state = "error"; } } }
    }
    Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: stp.running = true }
    Process {
        id: stp
        command: ["python3", "-I", w.script, "status"]
        stdout: StdioCollector { onStreamFinished: {
            try {
                const r = JSON.parse(text);
                if (r.ok) { w.st = r; w.stState = "ok"; } else w.stState = r.error === "no-config" ? "no-config" : "down";
            } catch (e) { w.stState = "down"; } } }
    }
    Process { id: actor; stdout: StdioCollector { onStreamFinished: w.refresh() } }

    // ---- picker data ----
    property string query: ""
    property string domainFilter: ""
    property var results: []
    property int resultTotal: 0
    property bool searching: false
    function runSearch() { searchTimer.restart(); }
    Timer { id: searchTimer; interval: 220; onTriggered: { sp.command = ["python3", "-I", w.script, "search", w.query, w.domainFilter]; sp.running = true; w.searching = true; } }
    Process { id: sp
        stdout: StdioCollector { onStreamFinished: {
            w.searching = false;
            try { const r = JSON.parse(text); if (r.ok) { w.results = r.entities; w.resultTotal = r.total; } } catch (e) { } } }
    }

    // ---- the tile ----
    Row {
        id: row
        anchors.centerIn: parent; spacing: 8
        Icon { anchors.verticalCenter: parent.verticalCenter; name: w.toggles.length === 0 ? "home" : (w.onCount > 0 ? "lightbulb" : "light_off"); size: 24
            color: w.onCount > 0 ? Theme.warn : Theme.textDim
            Behavior on color { ColorAnimation { duration: 250 } }
            Rectangle {   // health dot
                width: 8; height: 8; radius: 4; color: w.dot; border.width: 1.5; border.color: Theme.dockFill
                anchors { right: parent.right; top: parent.top; rightMargin: -3; topMargin: -1 }
                Behavior on color { ColorAnimation { duration: 300 } } } }
        Text { anchors.verticalCenter: parent.verticalCenter; visible: w.state === "ok" && w.toggles.length > 0; text: w.onCount + "/" + w.toggles.length
            color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
    }

    Popover {
        id: pop
        target: w
        panelWidth: 380
        panelHeight: w.mode === "pick" ? 500 : (w.state === "ok" ? listCol.implicitHeight + 28 : 150)

        Text { visible: w.state !== "ok"; anchors.centerIn: parent; width: parent.width - 40; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
            text: w.state === "no-config" ? "Create ~/.config/quickdock/ha.json with your Home Assistant url and token."
                : w.state === "loading" ? "Loading…" : "Couldn't reach Home Assistant." }

        // ================= list: status + pinned entities =================
        Column {
            id: listCol
            visible: w.state === "ok" && w.mode === "list"
            x: 14; y: 14; width: parent.width - 28
            spacing: 8
            Text { text: "Home"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
            Rectangle {   // Home Assistant status card
                width: parent.width; radius: 14; color: Theme.tileFill
                height: statCol.implicitHeight + 20
                Column { id: statCol; x: 12; y: 10; width: parent.width - 24; spacing: 6
                    Row { spacing: 8
                        Rectangle { width: 10; height: 10; radius: 5; color: w.dot; anchors.verticalCenter: parent.verticalCenter }
                        Text { textFormat: Text.PlainText; anchors.verticalCenter: parent.verticalCenter; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                            text: w.stState === "ok" ? "Home Assistant " + w.st.version + " · " + (w.st.state === "RUNNING" ? "running" : w.st.state.toLowerCase())
                                : (w.stState === "loading" ? "Checking…" : (w.stState === "no-config" ? "Not configured" : "Unreachable")) } }
                    Row { visible: w.stState === "ok"; spacing: 14
                        Text { text: w.st ? w.st.entities + " entities" : ""; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                        Text { text: w.st ? w.st.unavailable + " unavailable" : ""; font.family: Theme.font; font.pixelSize: 12
                            color: w.st && w.st.unavailable > 0 ? Theme.warn : Theme.textDim }
                        Text { text: w.st ? w.st.latencyMs + " ms" : ""; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 } }
                    Repeater { model: w.st ? w.st.unavailableList.slice(0, 3) : []
                        delegate: Text { textFormat: Text.PlainText; required property var modelData; width: statCol.width; elide: Text.ElideRight
                            text: "•  " + modelData.name; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 } }
                }
            }

            Repeater {
                model: w.ents
                delegate: Rectangle {
                    id: er
                    required property var modelData
                    readonly property bool on: modelData.state === "on"
                    readonly property bool tog: w.isToggle(modelData)
                    readonly property bool renaming: w.renamingId === modelData.id
                    width: listCol.width; height: w.rowHeight(modelData); radius: 14
                    color: on ? Qt.rgba(1, 0.72, 0.3, 0.14) : Theme.tileFill
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Behavior on height { NumberAnimation { duration: 160 } }
                    MouseArea { id: hov; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

                    Icon { x: 12; y: 12; name: w.iconFor(er.modelData, er.on); size: 20; color: er.on ? Theme.warn : Theme.textDim }
                    // name, or an inline editor while renaming
                    Text { visible: !er.renaming; textFormat: Text.PlainText; x: 42; y: 13; width: parent.width - 42 - 150; elide: Text.ElideRight
                        text: w.displayName(er.modelData); color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                    Rectangle { visible: er.renaming; x: 38; y: 7; width: parent.width - 38 - 100; height: 30; radius: 8; color: Qt.rgba(1, 1, 1, 0.1)
                        border.width: 1; border.color: Theme.accent
                        TextInput { id: rn; anchors { fill: parent; leftMargin: 8; rightMargin: 8 } verticalAlignment: TextInput.AlignVCenter
                            text: w.displayName(er.modelData); selectByMouse: true; clip: true
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                            onVisibleChanged: if (visible) { forceActiveFocus(); selectAll(); }
                            onAccepted: w.rename(er.modelData.id, text)
                            Keys.onEscapePressed: w.renamingId = "" } }
                    Row { visible: er.renaming; x: parent.width - 94; y: 8; spacing: 4
                        IconButton { width: 28; height: 28; radius: 14; icon: "check"; onClicked: w.rename(er.modelData.id, rn.text) }
                        IconButton { width: 28; height: 28; radius: 14; icon: "close"; onClicked: w.renamingId = "" } }

                    // hover actions: rename / unpin
                    Row { visible: !er.renaming && hov.containsMouse; y: 8; x: parent.width - (er.tog || w.isRun(er.modelData) ? 150 : 100); spacing: 2
                        IconButton { width: 28; height: 28; radius: 14; icon: "edit"; onClicked: w.renamingId = er.modelData.id }
                        IconButton { width: 28; height: 28; radius: 14; icon: "keep_off"; onClicked: w.unpin(er.modelData.id) } }

                    // control: switch / run / value
                    Rectangle {   // switch
                        visible: er.tog && !er.renaming
                        anchors { right: parent.right; rightMargin: 12; top: parent.top; topMargin: 11 }
                        width: 40; height: 22; radius: 11; color: er.on ? Theme.warn : Qt.rgba(1, 1, 1, 0.15)
                        Behavior on color { ColorAnimation { duration: 180 } }
                        Rectangle { width: 16; height: 16; radius: 8; y: 3; x: er.on ? 21 : 3; color: "white"
                            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutBack } } }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: w.toggleEntity(er.modelData) }
                    }
                    Rectangle {   // run (scene / script / button)
                        visible: w.isRun(er.modelData) && !er.renaming
                        anchors { right: parent.right; rightMargin: 10; top: parent.top; topMargin: 8 }
                        width: 62; height: 28; radius: 14; color: Theme.accent
                        Text { anchors.centerIn: parent; text: "Run"; color: "#101218"; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: w.runEntity(er.modelData) }
                    }
                    Text { visible: !er.tog && !w.isRun(er.modelData) && !er.renaming; textFormat: Text.PlainText
                        anchors { right: parent.right; rightMargin: 14; top: parent.top; topMargin: 14 }
                        text: w.valueText(er.modelData); color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Slider {
                        visible: er.modelData.dimmable && er.on && er.modelData.brightness !== null
                        anchors { left: parent.left; leftMargin: 12; right: parent.right; rightMargin: 12; bottom: parent.bottom; bottomMargin: 6 }
                        icon: "brightness_6"; value: er.modelData.brightness ?? 0
                        onMoved: v => w.call("light", "turn_on", er.modelData.id, { brightness_pct: Math.max(1, Math.round(v * 100)) })
                    }
                }
            }
            Text { visible: w.pinned.length === 0; topPadding: 6; width: parent.width; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                text: "Nothing pinned yet"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
            Rectangle {   // pin more
                width: parent.width; height: 40; radius: 12; color: pm.containsMouse ? Theme.tileFillHover : Qt.rgba(1, 1, 1, 0.06)
                border.width: 1; border.color: Theme.hairlineHover
                Behavior on color { ColorAnimation { duration: 120 } }
                Row { anchors.centerIn: parent; spacing: 6
                    Icon { name: "add"; size: 18; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Pin more entities"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter } }
                MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { w.mode = "pick"; w.query = ""; w.domainFilter = ""; w.runSearch(); sf.text = ""; sf.forceActiveFocus(); } }
            }
        }

        // ================= picker: search all entities, pin with one click =================
        Column {
            visible: w.state === "ok" && w.mode === "pick"
            x: 14; y: 14; width: parent.width - 28; spacing: 8
            Row { spacing: 8; height: 34
                IconButton { width: 32; height: 32; radius: 16; icon: "arrow_back"; onClicked: { w.mode = "list"; w.refresh(); } }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Pin entities"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold } }
            Rectangle {
                width: parent.width; height: 38; radius: 12; color: Theme.tileFill
                border.width: 1; border.color: sf.activeFocus ? Theme.accent : Theme.hairline
                Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 18; color: Theme.textDim }
                TextInput { id: sf
                    anchors { left: parent.left; leftMargin: 36; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13; clip: true; selectByMouse: true
                    onTextChanged: { w.query = text; w.runSearch(); }
                    Text { visible: !sf.text; text: "Search all " + (w.st ? w.st.entities : "") + " entities"; color: Theme.textDim; font: sf.font; anchors.verticalCenter: parent.verticalCenter } }
            }
            Flow {   // domain filter
                width: parent.width; spacing: 6
                Repeater {
                    model: [ { l: "All", d: "" }, { l: "Lights", d: "light" }, { l: "Switches", d: "switch" }, { l: "Sensors", d: "sensor" },
                             { l: "Climate", d: "climate" }, { l: "Covers", d: "cover" }, { l: "Scenes", d: "scene" } ]
                    delegate: Rectangle { required property var modelData
                        readonly property bool sel: w.domainFilter === modelData.d
                        height: 26; width: fl.implicitWidth + 22; radius: 13; color: sel ? Theme.accent : Qt.rgba(1, 1, 1, 0.08)
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Text { id: fl; anchors.centerIn: parent; text: modelData.l; color: sel ? "#101218" : Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { w.domainFilter = modelData.d; w.runSearch(); } } }
                }
            }
            Text { text: w.searching ? "Searching…" : (w.resultTotal + " match" + (w.resultTotal === 1 ? "" : "es") + (w.resultTotal > w.results.length ? " · showing " + w.results.length : ""))
                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 }
            Repeater {
                model: w.results.slice(0, 8)
                delegate: Rectangle {
                    id: pr
                    required property var modelData
                    readonly property bool isPinned: w.pinned.indexOf(modelData.id) >= 0
                    width: parent.width; height: 42; radius: 10; color: prm.containsMouse ? Theme.tileFillHover : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Icon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: w.iconFor(pr.modelData, pr.modelData.state === "on"); size: 20
                        color: pr.modelData.state === "on" ? Theme.warn : Theme.textDim }
                    Column { x: 38; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 38 - 90
                        Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: pr.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                        Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: pr.modelData.id; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10 } }
                    Text { textFormat: Text.PlainText; anchors { right: pinBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter } text: w.valueText(pr.modelData)
                        color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 }
                    IconButton { id: pinBtn; width: 30; height: 30; radius: 15; anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                        icon: pr.isPinned ? "keep_off" : "keep"; active: pr.isPinned
                        onClicked: pr.isPinned ? w.unpin(pr.modelData.id) : w.pin(pr.modelData.id) }
                    MouseArea { id: prm; anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: pinBtn.left } hoverEnabled: true; acceptedButtons: Qt.NoButton }
                }
            }
        }
    }
}
