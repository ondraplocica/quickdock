import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import "../../core"

Tile {
    id: w
    implicitWidth: icons.implicitWidth + 28

    // ---------- state ----------
    property int page: 0                     // 0 quick settings, 1 dock settings
    property bool powerOpen: false
    property bool eth: false
    property string uptimeText: ""
    property real brightness: 0
    property bool hasBacklight: false
    readonly property string user: Quickshell.env("USER") || "user"
    property string fullName: user

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [w.sink, w.source] }
    readonly property real vol: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool volMuted: sink && sink.audio ? sink.audio.muted : false
    readonly property real micVol: source && source.audio ? source.audio.volume : 0
    readonly property bool micMuted: source && source.audio ? source.audio.muted : true
    readonly property var bt: Bluetooth.defaultAdapter
    readonly property var btConnected: bt ? bt.devices.values.filter(d => d.connected) : []

    function toggle() { if (!pop.open) pollNow(); pop.open = !pop.open; }
    // Reset to the first page only after the dropdown has faded out, so it never slides in on reopen.
    Timer { id: resetPage; interval: 450; onTriggered: { w.page = 0; w.powerOpen = false; w.devOpen = false; } }
    Connections { target: pop; function onOpenChanged() { if (pop.open) { resetPage.stop(); w.step = 0; revealTimer.restart(); } else resetPage.restart(); } }
    onClicked: toggle()
    function openSettings() { resetPage.stop(); page = 1; powerOpen = false; pop.open = true; }
    function pollNow() { pEth.running = true; Quick.poll(); pUp.running = true; pBright.running = true; }
    function run(cmd) { Quickshell.execDetached(cmd); }
    function later() { repoll.restart(); }
    Timer { id: repoll; interval: 1200; onTriggered: w.pollNow() }
    Timer { interval: 8000; running: true; repeat: true; triggeredOnStart: true; onTriggered: w.pollNow() }

    function setMicVol(v) { if (source && source.audio) { source.audio.volume = v; if (source.audio.muted && v > 0) source.audio.muted = false; } }
    readonly property var mp: Mpris.players.values.find(x => x.isPlaying) ?? Mpris.players.values[0] ?? null
    function setVol(v) { if (sink && sink.audio) { sink.audio.volume = v; if (sink.audio.muted && v > 0) sink.audio.muted = false; } }
    WheelHandler { onWheel: e => w.setVol(Math.max(0, Math.min(1, w.vol + (e.angleDelta.y > 0 ? 0.03 : -0.03)))) }

    // Split the current segments into left / centre / right zones (first segment left, latter half right).
    function toSections() {
        const list = Dock.cfg.widgets.filter(x => x[0] !== "@");
        const segs = [[]];
        list.forEach(id => { if (id === "|") segs.push([]); else segs[segs.length - 1].push(id); });
        const S = segs.filter(a => a.length);
        const n = S.length;
        const join = arr => arr.reduce((acc, g, i) => acc.concat(i ? ["|"] : [], g), []);
        let L = [], C = S, R = [];
        if (n >= 3) { L = S.slice(0, 1); R = S.slice(Math.ceil((n + 1) / 2)); C = S.slice(1, Math.ceil((n + 1) / 2)); }
        else if (n === 2) { L = S.slice(0, 1); C = []; R = S.slice(1); }
        return ["@left"].concat(join(L), ["@center"], join(C), ["@right"], join(R));
    }
    function hasMarkers() { return Dock.cfg.widgets.some(x => x[0] === "@"); }
    function nodeName(n) { return n ? (n.description || n.nickname || n.name || "") : ""; }
    // ---- audio device dropdowns (output / input) ----
    property bool devOpen: false
    property int step: 0                    // staggered entrance: modules appear one after another when the panel opens
    Timer { id: revealTimer; interval: 55; repeat: true; onTriggered: { w.step++; if (w.step > 10) stop(); } }
    property string devKind: "out"          // "out" | "in"
    readonly property var hwNodes: Pipewire.nodes.values.filter(n => !n.isStream)
    PwObjectTracker { objects: w.hwNodes }  // bind them so `properties` (media.class) is readable
    function mediaClass(n) { return (n.properties && n.properties["media.class"]) || ""; }
    function listFor(kind) {
        const c = hwNodes.filter(n => { const k = mediaClass(n); return kind === "out" ? (k ? k === "Audio/Sink" : n.isSink) : (k ? k === "Audio/Source" : (!n.isSink && !/monitor/i.test(n.name || ""))); });
        return c.filter(n => !/driver/i.test(n.name || "") && !/driver/i.test(nodeName(n))).sort((x, y) => nodeName(x).localeCompare(nodeName(y)));
    }
    function toggleDev(kind) { if (devOpen && devKind === kind) devOpen = false; else { devKind = kind; devOpen = true; } }
    function selectDevice(kind, n) {
        if (kind === "out") Pipewire.preferredDefaultAudioSink = n; else Pipewire.preferredDefaultAudioSource = n;
        devOpen = false;
    }
    function action(arg) { resetPage.stop(); step = 99; page = 0; if (arg === "out" || arg === "in") { devKind = arg; devOpen = true; } pop.open = true; }   // `ipc call dock action quicksettings out`
    Connections { target: Dock; function onCloseAll() { w.devOpen = false; } }

    // What the panel shows: module order, hidden modules and the tiles of each zone all come from
    // widgetConfig.quicksettings (see core/QsLayout.qml); the defaults are the original fixed panel.
    // Edit them in the quick-settings builder (footer pencil, or `ipc call dock qsbuilder`).
    readonly property var lay: QsLayout.view()
    function modVisible(m) {
        switch (m) {
        case "shortcuts": return lay.shortcuts.length > 0;
        case "display": return hasBacklight;
        case "player": return mp !== null;
        }
        return true;    // top / sound / mic
    }
    readonly property var visibleModules: lay.order.filter(m => lay.hiddenMods.indexOf(m) < 0 && modVisible(m))
    function tileSub(id) {
        if (Quick.busy(id)) return "Working…";
        switch (id) {
        case "vpn": return Quick.vpnOn ? "Tailscale" : "Off";
        case "dnd": return Quick.dndOn ? "Do Not Disturb" : "Off";
        }
        return Quick.hasState(id) ? (Quick.isOn(id) ? "On" : "Off") : "";
    }
    function tileIcon(id) { const m = Quick.meta(id); return m ? m.icon : "bolt"; }

    // ---------- backends ----------
    Process { id: pEth; command: ["sh", "-c", "nmcli -t -f TYPE,STATE dev | grep -E '^(ethernet|wifi):' | head -1"]
        stdout: StdioCollector { onStreamFinished: w.eth = text.indexOf(":connected") >= 0 } }
    Process { id: pUp; command: ["sh", "-c", "cut -d' ' -f1 /proc/uptime"]
        stdout: StdioCollector { onStreamFinished: {
            const s = Math.floor(parseFloat(text)), d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
            const part = (n, u) => n + " " + u + (n === 1 ? "" : "s");
            w.uptimeText = "up " + (d ? part(d, "day") + ", " : "") + (h ? part(h, "hour") + ", " : "") + part(m, "minute");
        } } }
    Process { id: pBright; command: ["sh", "-c", "brightnessctl -m -c backlight 2>/dev/null | head -1"]
        stdout: StdioCollector { onStreamFinished: {
            const f = text.trim().split(",");
            w.hasBacklight = f.length >= 4;
            if (w.hasBacklight) w.brightness = parseInt(f[3]) / 100;
        } } }
    Process { id: pName; command: ["sh", "-c", "getent passwd $USER | cut -d: -f5 | cut -d, -f1"]; running: true
        stdout: StdioCollector { onStreamFinished: if (text.trim()) w.fullName = text.trim() } }
    // ---------- dock tile ----------
    Row {
        id: icons
        anchors.centerIn: parent; spacing: 12
        Icon { name: w.eth ? "lan" : "wifi_off"; size: 22; color: w.eth ? Theme.text : Theme.textDim }
        Icon { name: w.volMuted || w.vol === 0 ? "volume_off" : (w.vol < 0.4 ? "volume_down" : "volume_up"); size: 22 }
        Icon { name: w.bt && w.bt.enabled ? "bluetooth" : "bluetooth_disabled"; size: 22; color: w.bt && w.bt.enabled ? Theme.text : Theme.textDim }
    }

    // ---- macOS-style building blocks ----
    // Card: a tonal Material surface (primary container when `lit`), translucent with the panel opacity.
    component Card: Rectangle {
        id: card
        property bool lit: false
        default property alias content: inner.data
        radius: Theme.square ? 10 : QsStyle.cardRadius
        color: card.lit ? QsStyle.cardOn : QsStyle.card
        Behavior on color { ColorAnimation { duration: 140 } }
        Item { id: inner; anchors.fill: parent }
    }
    component Dot: Rectangle {
        id: dot
        property string icon: ""
        property bool on: false
        property int size: 32
        width: size; height: size; radius: size / 2
        color: dot.on ? QsStyle.dotOn : QsStyle.iconBg
        Behavior on color { ColorAnimation { duration: 140 } }
        Icon { anchors.centerIn: parent; name: dot.icon; size: Math.round(dot.size * 0.54); filled: dot.on
            color: dot.on ? QsStyle.onDot : QsStyle.textDim }
        onOnChanged: pop2.restart()
        SequentialAnimation {   // little spring when toggled
            id: pop2
            NumberAnimation { target: dot; property: "scale"; to: 1.14; duration: 110; easing.type: Easing.OutQuad }
            NumberAnimation { target: dot; property: "scale"; to: 1; duration: 240; easing.type: Easing.OutBack }
        }
    }
    component DeviceList: Column {
        id: dl
        property string kind: "out"
        visible: w.devOpen && w.devKind === kind
        width: parent ? parent.width : 0
        spacing: 2
        Repeater {
            model: dl.visible ? w.listFor(dl.kind) : []
            delegate: Rectangle {
                id: dr
                required property var modelData
                readonly property bool cur: dl.kind === "out" ? modelData === w.sink : modelData === w.source
                width: dl.width; height: 34; radius: 10
                color: cur ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18) : (dm.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                Behavior on color { ColorAnimation { duration: 120 } }
                Icon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: dl.kind === "out" ? "volume_up" : "mic"; size: 17; color: dr.cur ? Theme.accent : Theme.textDim }
                Text { textFormat: Text.PlainText; x: 34; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 34 - 30; elide: Text.ElideRight
                    text: w.nodeName(dr.modelData); color: QsStyle.text; font.family: Theme.font; font.pixelSize: 12; font.weight: dr.cur ? Font.DemiBold : Font.Normal }
                Icon { visible: dr.cur; anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } name: "check"; size: 17; color: Theme.accent }
                MouseArea { id: dm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.selectDevice(dl.kind, dr.modelData) }
            }
        }
        Text { visible: dl.visible && w.listFor(dl.kind).length === 0; text: "No devices found"; color: QsStyle.textDim; font.family: Theme.font; font.pixelSize: 12; topPadding: 4 }
    }

    // module: connectivity card + top tiles (zones.conn / zones.top)
    function tileAct(t) {
        if (t.id === "bt") { if (bt) bt.enabled = !bt.enabled; }
        else if (t.tile) Quick.toggle(t.id);
    }
    // module: top block -- Network, Bluetooth, then every tile of zones.conn and zones.top, as equal tiles in two columns
    Component { id: cTop
        Flow {   // wraps: two equal tiles per row, an odd last tile spans the full row
            id: tg
            property int rank: 0
            opacity: w.step > rank ? 1 : 0
            transform: Translate { y: w.step > tg.rank ? 0 : 12; Behavior on y { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } } }
            Behavior on opacity { NumberAnimation { duration: 280 } }
            width: parent.width; spacing: 10
            readonly property var tiles: {
                const mk = id => ({ id: id, tile: true, icon: w.tileIcon(id), title: Quick.label(id), sub: w.tileSub(id), on: Quick.isOn(id) });
                return [
                    { id: "eth", tile: false, icon: "settings_ethernet", title: "Network", sub: w.eth ? "Ethernet" : "Disconnected", on: w.eth },
                    { id: "bt", tile: false, icon: w.bt && w.bt.enabled ? "bluetooth" : "bluetooth_disabled", title: "Bluetooth",
                      sub: w.bt && w.bt.enabled ? (w.btConnected.length ? w.btConnected.map(d => d.name).join(", ") : "On") : "Off", on: w.bt ? w.bt.enabled : false }
                ].concat(w.lay.conn.map(mk)).concat(w.lay.topWide !== "" ? [mk(w.lay.topWide)] : []).concat(w.lay.topSquares.map(mk));
            }
            Repeater {
                model: tg.tiles
                delegate: Card {
                    id: tc
                    required property var modelData
                    required property int index
                    lit: modelData.on
                    // an odd last tile spans the full row
                    width: (tg.tiles.length % 2 === 1 && index === tg.tiles.length - 1) ? tg.width : (tg.width - tg.spacing) / 2
                    height: 70
                    scale: tcm.pressed ? 0.97 : 1
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                    Dot { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 40; icon: tc.modelData.icon; on: tc.modelData.on }
                    Column { x: 62; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 70
                        Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: tc.modelData.title; color: QsStyle.ink(tc.modelData.on)
                            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: tc.modelData.sub; color: QsStyle.inkDim(tc.modelData.on)
                            font.family: Theme.font; font.pixelSize: 11 } }
                    MouseArea { id: tcm; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: w.tileAct(tc.modelData) }
                }
            }
        }
    }

    // module: shortcuts grid (zones.shortcuts)
    Component { id: cShortcuts
        Flow {   // up to four cards per row; with fewer than four they share the row evenly
            id: sg
            property int rank: 0
            readonly property int cols: Math.max(1, Math.min(4, w.lay.shortcuts.length))
            opacity: w.step > rank ? 1 : 0
            transform: Translate { y: w.step > sg.rank ? 0 : 12; Behavior on y { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } } }
            Behavior on opacity { NumberAnimation { duration: 280 } }
            width: parent.width; spacing: 10
            Repeater {
                model: w.lay.shortcuts
                delegate: Card {
                    id: st1
                    required property string modelData
                    lit: Quick.isOn(modelData)
                    width: (sg.width - (sg.cols - 1) * sg.spacing) / sg.cols; height: 76
                    scale: stm.pressed ? 0.94 : 1
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                    Column { anchors.centerIn: parent; spacing: 5; width: parent.width - 8
                        Dot { anchors.horizontalCenter: parent.horizontalCenter; size: 36; icon: w.tileIcon(st1.modelData); on: Quick.isOn(st1.modelData) }
                        Text { textFormat: Text.PlainText; anchors.horizontalCenter: parent.horizontalCenter; width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                            text: Quick.label(st1.modelData); color: QsStyle.ink(Quick.isOn(st1.modelData)); font.family: Theme.font; font.pixelSize: 10; font.weight: Font.Medium } }
                    MouseArea { id: stm; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quick.toggle(st1.modelData) }
                }
            }
        }
    }

    // module: Display (only with a real backlight)
    Component { id: cDisplay
        Card {
            property int rank: 0
            implicitHeight: height
            width: parent.width; height: 66
            opacity: w.step > rank ? 1 : 0
            transform: Translate { y: w.step > rank ? 0 : 12; Behavior on y { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } } }
            Behavior on opacity { NumberAnimation { duration: 280 } }
            Column { x: 12; y: 10; width: parent.width - 24; spacing: 6
                Text { text: "Display"; color: QsStyle.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                MacSlider { width: parent.width; icon: "brightness_medium"; value: w.brightness
                    onMoved: v => { w.brightness = v; w.run(["brightnessctl", "-c", "backlight", "set", Math.max(1, Math.round(v * 100)) + "%"]); } } }
        }
    }
    // module: Sound
    Component { id: cSound
        Card {
            property int rank: 0
            implicitHeight: height
            width: parent.width; height: soundCol.implicitHeight + 22
            opacity: w.step > rank ? 1 : 0
            transform: Translate { y: w.step > rank ? 0 : 12; Behavior on y { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } } }
            Behavior on opacity { NumberAnimation { duration: 280 } }
            Column { id: soundCol; x: 12; y: 10; width: parent.width - 24; spacing: 6
                Row { width: parent.width; height: 20
                    Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width - sdev.width - 6; text: "Sound"; color: QsStyle.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Rectangle { id: sdev; anchors.verticalCenter: parent.verticalCenter; height: 22; width: Math.min(200, sdl.implicitWidth + 40); radius: 11
                        color: sdm.containsMouse || (w.devOpen && w.devKind === "out") ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Text { id: sdl; textFormat: Text.PlainText; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            width: Math.min(150, implicitWidth); elide: Text.ElideRight; text: w.nodeName(w.sink) || "No output"; color: QsStyle.textDim; font.family: Theme.font; font.pixelSize: 11 }
                        Icon { anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter } name: "expand_more"; size: 16; color: Theme.text
                            rotation: w.devOpen && w.devKind === "out" ? 180 : 0
                            Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } } }
                        MouseArea { id: sdm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.toggleDev("out") } }
                }
                MacSlider { width: parent.width; icon: w.volMuted || w.vol === 0 ? "volume_off" : (w.vol < 0.4 ? "volume_down" : "volume_up"); value: w.vol; dim: w.volMuted
                    onMoved: v => w.setVol(v)
                    onIconClicked: { if (w.sink && w.sink.audio) w.sink.audio.muted = !w.sink.audio.muted; } }
                DeviceList { kind: "out" }
            }
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.RightButton; onClicked: w.toggleDev("out") }
        }
    }
    // module: Microphone
    Component { id: cMic
        Card {
            property int rank: 0
            implicitHeight: height
            width: parent.width; height: micCol.implicitHeight + 22
            opacity: w.step > rank ? 1 : 0
            transform: Translate { y: w.step > rank ? 0 : 12; Behavior on y { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } } }
            Behavior on opacity { NumberAnimation { duration: 280 } }
            Column { id: micCol; x: 12; y: 10; width: parent.width - 24; spacing: 6
                Row { width: parent.width; height: 20
                    Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width - mdev.width - 6; text: "Microphone"; color: QsStyle.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Rectangle { id: mdev; anchors.verticalCenter: parent.verticalCenter; height: 22; width: Math.min(200, mdl.implicitWidth + 40); radius: 11
                        color: mdm.containsMouse || (w.devOpen && w.devKind === "in") ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Text { id: mdl; textFormat: Text.PlainText; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            width: Math.min(150, implicitWidth); elide: Text.ElideRight; text: w.nodeName(w.source) || "No input"; color: QsStyle.textDim; font.family: Theme.font; font.pixelSize: 11 }
                        Icon { anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter } name: "expand_more"; size: 16; color: Theme.text
                            rotation: w.devOpen && w.devKind === "in" ? 180 : 0
                            Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } } }
                        MouseArea { id: mdm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.toggleDev("in") } }
                }
                MacSlider { width: parent.width; icon: w.micMuted ? "mic_off" : "mic"; value: w.micVol; dim: w.micMuted
                    onMoved: v => w.setMicVol(v)
                    onIconClicked: { if (w.source && w.source.audio) w.source.audio.muted = !w.source.audio.muted; } }
                DeviceList { kind: "in" }
            }
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.RightButton; onClicked: w.toggleDev("in") }
        }
    }
    // module: Now Playing
    Component { id: cPlayer
        Card {
            property int rank: 0
            implicitHeight: height
            width: parent.width; height: 76
            opacity: w.step > rank ? 1 : 0
            transform: Translate { y: w.step > rank ? 0 : 12; Behavior on y { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } } }
            Behavior on opacity { NumberAnimation { duration: 280 } }
            Row { x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 12; width: parent.width - 24
                Rectangle { width: 52; height: 52; radius: 10; clip: true; color: Qt.rgba(1, 1, 1, 0.1); anchors.verticalCenter: parent.verticalCenter
                    Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; source: w.mp ? (w.mp.trackArtUrl || "") : "" }
                    Icon { anchors.centerIn: parent; name: "music_note"; size: 22; color: QsStyle.textDim; visible: !w.mp || !w.mp.trackArtUrl } }
                Column { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 52 - 12 - 108 - 12
                    Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: w.mp ? (w.mp.trackTitle || "Unknown") : ""; color: QsStyle.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: w.mp ? (w.mp.trackArtist || "") : ""; color: QsStyle.textDim; font.family: Theme.font; font.pixelSize: 11 } }
                Row { anchors.verticalCenter: parent.verticalCenter; spacing: 0
                    IconButton { width: 34; height: 34; radius: 17; icon: "skip_previous"; onClicked: { if (w.mp) w.mp.previous(); } }
                    IconButton { width: 34; height: 34; radius: 17; icon: w.mp && w.mp.isPlaying ? "pause" : "play_arrow"; onClicked: { if (w.mp) w.mp.togglePlaying(); } }
                    IconButton { width: 34; height: 34; radius: 17; icon: "skip_next"; onClicked: { if (w.mp) w.mp.next(); } } }
            }
        }
    }

    Popover {
        id: pop
        target: w
        fancy: true
        bare: true
        panelWidth: w.page === 0 ? 360 : 440
        panelHeight: (w.page === 0 ? qs.implicitHeight + 28 : st.implicitHeight + 36)

        Item {
            anchors.fill: parent

            // ---- the panel: one tonal Material surface; translucent when Panel opacity < 100% (Hyprland blurs behind it) ----
            Rectangle {
                anchors.fill: parent
                radius: Theme.square ? 12 : QsStyle.panelRadius
                color: QsStyle.panel
                border.width: 1; border.color: QsStyle.panelEdge
            }

            // ======== page 0: quick settings (macOS Control Center style) ========
            Column {
                id: qs
                width: parent.width - 28; y: 14
                x: w.page === 0 ? 14 : -parent.width
                opacity: w.page === 0 ? 1 : 0
                spacing: 10
                Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200 } }

                // ---- modules, in the order set in the builder (widgetConfig.quicksettings.order / hidden) ----
                Repeater {
                    model: w.visibleModules
                    delegate: Loader {
                        id: modLoader
                        required property string modelData
                        required property int index
                        width: qs.width     // height follows the module's implicitHeight (an explicit height would resize the item)
                        sourceComponent: ({ top: cTop, shortcuts: cShortcuts, display: cDisplay, sound: cSound, mic: cMic, player: cPlayer })[modelData]
                        onLoaded: item.rank = Qt.binding(() => modLoader.index)
                    }
                }

                Row {   // power menu (two-step: nothing happens until you pick one)
                    visible: w.powerOpen
                    width: parent.width; spacing: 8
                    Repeater {
                        model: [ { l: "Suspend", i: "bedtime", c: ["systemctl", "suspend"] },
                                 { l: "Reboot", i: "restart_alt", c: ["systemctl", "reboot"] },
                                 { l: "Power off", i: "power_settings_new", c: ["systemctl", "poweroff"] } ]
                        delegate: Rectangle {
                            required property var modelData
                            width: (parent.width - 16) / 3; height: 40; radius: 20
                            color: pm.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07)
                            Row { anchors.centerIn: parent; spacing: 6
                                Icon { name: modelData.i; size: 17; color: Theme.accent }
                                Text { text: modelData.l; color: QsStyle.text; font.family: Theme.font; font.pixelSize: 12 } }
                            MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { pop.open = false; w.run(modelData.c); } }
                        }
                    }
                }

                // ---- footer: who you are + keep awake / lock / power / settings / edit ----
                Row {
                    opacity: w.step > w.visibleModules.length ? 1 : 0
                    transform: Translate { y: w.step > w.visibleModules.length ? 0 : 12; Behavior on y { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } } }
                    Behavior on opacity { NumberAnimation { duration: 280 } }
                    width: parent.width; height: 38; spacing: 8
                    Item {
                        id: av
                        width: 34; height: 34; anchors.verticalCenter: parent.verticalCenter
                        Rectangle { id: avMask; anchors.fill: parent; radius: 17; visible: false; layer.enabled: true }
                        Rectangle { anchors.fill: parent; radius: 17; color: Theme.accent
                            Text { anchors.centerIn: parent; text: w.fullName.split(" ").map(x => x[0]).slice(0, 2).join("").toUpperCase()
                                color: "#101218"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Bold } }
                        Image {
                            anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true
                            source: (w.config.avatar ? "file://" + w.config.avatar : "file:///var/lib/AccountsService/icons/" + w.user)
                            visible: status === Image.Ready
                            layer.enabled: true
                            layer.effect: MultiEffect { maskEnabled: true; maskSource: avMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                        }
                    }
                    Column { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 34 - 8 - 4 * 32 - 3 * 4 - 8
                        Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: w.fullName; color: QsStyle.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                        Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: w.uptimeText; color: QsStyle.textDim; font.family: Theme.font; font.pixelSize: 10 } }
                    Row { anchors.verticalCenter: parent.verticalCenter; spacing: 4
                        IconButton { width: 32; height: 32; radius: 16; icon: "lock"; onClicked: { pop.open = false; w.run(["dms", "ipc", "call", "lock", "lock"]); } }
                        IconButton { width: 32; height: 32; radius: 16; icon: "power_settings_new"; active: w.powerOpen; onClicked: w.powerOpen = !w.powerOpen }
                        IconButton { width: 32; height: 32; radius: 16; icon: "settings"; onClicked: w.page = 1 }
                        IconButton { width: 32; height: 32; radius: 16; icon: "edit"; onClicked: { pop.open = false; Dock.openQsBuilder(); } }
                    }
                }
            }

            // ======== page 1: dock settings ========
            Column {
                id: st
                width: parent.width - 36; y: 18
                x: w.page === 1 ? 18 : parent.width
                opacity: w.page === 1 ? 1 : 0
                spacing: 12
                Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200 } }

                Row { spacing: 8; height: 38
                    IconButton { icon: "arrow_back"; onClicked: w.page = 0 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Dock settings"
                        color: QsStyle.text; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold } }

                Row { width: parent.width; spacing: 8
                    Rectangle { width: (parent.width - 8) / 2; height: 40; radius: 14; color: bma.containsMouse ? Theme.tileFillHover : Qt.rgba(1, 1, 1, 0.07)
                        Row { anchors.centerIn: parent; spacing: 8
                            Icon { name: "dashboard_customize"; size: 19; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "Bar builder"; color: QsStyle.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter } }
                        MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { pop.open = false; Dock.openBuilder(); } } }
                    Rectangle { width: (parent.width - 8) / 2; height: 40; radius: 14; color: qma.containsMouse ? Theme.tileFillHover : Qt.rgba(1, 1, 1, 0.07)
                        Row { anchors.centerIn: parent; spacing: 8
                            Icon { name: "tune"; size: 19; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "Quick settings builder"; color: QsStyle.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter } }
                        MouseArea { id: qma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { pop.open = false; Dock.openQsBuilder(); } } }
                }

                Stepper { label: "Dropdown opacity (lower = more blur behind)"; valueText: Math.round(QsStyle.alpha * 100) + "%"
                    onMinus: Dock.save({ panelOpacity: Math.max(0.30, Math.round((QsStyle.alpha - 0.05) * 100) / 100) })
                    onPlus: Dock.save({ panelOpacity: Math.min(1.0, Math.round((QsStyle.alpha + 0.05) * 100) / 100) }) }

                Text { text: "Bar style"; color: QsStyle.textDim; font.family: Theme.font; font.pixelSize: 12 }
                Segmented { itemWidth: 124; current: Dock.style
                    options: [ { l: "Bar", v: "bar", i: "dock_to_bottom" }, { l: "Segments", v: "segments", i: "view_agenda" }, { l: "Pills", v: "pills", i: "pill" } ]
                    onPicked: v => Dock.save({ style: v }) }

                Text { text: "Layout"; color: QsStyle.textDim; font.family: Theme.font; font.pixelSize: 12 }
                Segmented { itemWidth: 150; current: Dock.cfg.layout === "sections" ? "sections" : "compact"
                    options: [ { l: "Compact", v: "compact", i: "pill" }, { l: "Left / centre / right", v: "sections", i: "view_week" } ]
                    onPicked: v => {
                        if (v === "sections" && !w.hasMarkers()) Dock.save({ layout: v, widgets: w.toSections() });
                        else Dock.save({ layout: v });
                    } }

                Text { text: "Position"; color: QsStyle.textDim; font.family: Theme.font; font.pixelSize: 12 }
                Row { spacing: 6
                    Segmented { itemWidth: 90; current: Dock.position
                        options: [ { l: "Top", v: "top", i: "vertical_align_top" }, { l: "Bottom", v: "bottom", i: "vertical_align_bottom" } ]
                        onPicked: v => Dock.save({ position: v }) }
                    Segmented { itemWidth: 110; current: Dock.fullWidth ? "full" : "fit"
                        options: [ { l: "Fit", v: "fit", i: "pill" }, { l: "Full width", v: "full", i: "width_full" } ]
                        onPicked: v => Dock.save({ fullWidth: v === "full" }) }
                }

                Text { text: "Corners"; color: QsStyle.textDim; font.family: Theme.font; font.pixelSize: 12 }
                Segmented { itemWidth: 124; current: Dock.square ? "square" : "round"
                    options: [ { l: "Rounded", v: "round" }, { l: "Square", v: "square" } ]
                    onPicked: v => Dock.save({ squareCorners: v === "square" }) }

                Stepper { label: "Bar scale"; valueText: Math.round(Dock.uiScale * 100) + "%"
                    onMinus: Dock.save({ scale: Math.max(0.7, Math.round((Dock.uiScale - 0.05) * 100) / 100) })
                    onPlus: Dock.save({ scale: Math.min(1.6, Math.round((Dock.uiScale + 0.05) * 100) / 100) }) }
                Stepper { label: "Dropdown scale"; valueText: Math.round(Dock.dropScale * 100) + "%"
                    onMinus: Dock.save({ dropdownScale: Math.max(0.7, Math.round((Dock.dropScale - 0.05) * 100) / 100) })
                    onPlus: Dock.save({ dropdownScale: Math.min(1.8, Math.round((Dock.dropScale + 0.05) * 100) / 100) }) }
                Stepper { label: "Opacity"; valueText: Math.round(Dock.barOpacity * 100) + "%"
                    onMinus: Dock.save({ opacity: Math.max(0.1, Math.round((Dock.barOpacity - 0.05) * 100) / 100) })
                    onPlus: Dock.save({ opacity: Math.min(1, Math.round((Dock.barOpacity + 0.05) * 100) / 100) }) }
                Stepper { label: "Section spacing"; valueText: Dock.segSpacing + " px"
                    onMinus: Dock.save({ spacing: Math.max(0, Dock.segSpacing - 2) })
                    onPlus: Dock.save({ spacing: Math.min(40, Dock.segSpacing + 2) }) }
                Stepper { label: "Distance from edge"; valueText: Dock.edgeMargin + " px"
                    onMinus: Dock.save({ margin: Math.max(0, Dock.edgeMargin - 2) })
                    onPlus: Dock.save({ margin: Math.min(80, Dock.edgeMargin + 2) }) }

                Text { text: "Accent colour"; color: QsStyle.textDim; font.family: Theme.font; font.pixelSize: 12 }
                Row {
                    spacing: 10
                    Repeater {
                        model: ["#8ab4ff", "#c4a7ff", "#ff9ec7", "#ffb74d", "#66d98b", "#5ce1e6"]
                        delegate: Rectangle {
                            required property string modelData
                            readonly property bool sel: Qt.colorEqual(Theme.accent, modelData)
                            width: 30; height: 30; radius: 15; color: modelData
                            border.width: sel ? 3 : 0; border.color: "white"
                            scale: cm.containsMouse ? 1.12 : 1
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                            MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: Dock.save({ accent: modelData }) }
                        }
                    }
                }

            }
        }
    }
}
