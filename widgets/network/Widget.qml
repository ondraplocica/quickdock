import QtQuick
import Quickshell.Io
import "../../core"

// Throughput from /proc/net/dev for the default-route interface (or widgetConfig.network.iface).
Tile {
    id: w
    implicitWidth: 200
    readonly property color downC: "#4cc9f0"
    readonly property color upC: "#a78bfa"
    property string iface: config.iface ?? ""        // empty = auto (default route)
    property string shown: ""                         // interface actually measured
    property real rx: 0                               // bytes/s
    property real tx: 0
    property var rxH: []
    property var txH: []
    property real rxPeak: 0
    property real txPeak: 0
    property real rxTotal: 0                          // bytes since boot on that interface
    property real txTotal: 0
    property var last: null
    property string ip: ""
    readonly property int keep: 60
    function toggle() { pop.open = !pop.open; if (pop.open) ipp.running = true; }
    onClicked: toggle()

    function fmt(b) {
        if (b < 1000) return Math.round(b) + " B/s";
        if (b < 1e6) return Math.round(b / 1000) + " KB/s";
        return (b / 1e6).toFixed(b < 1e7 ? 1 : 0) + " MB/s";
    }
    function fmtBytes(b) {
        if (b < 1e6) return Math.round(b / 1000) + " KB";
        if (b < 1e9) return (b / 1e6).toFixed(1) + " MB";
        return (b / 1e9).toFixed(2) + " GB";
    }

    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: proc.running = true }
    Process {
        id: proc
        command: ["sh", "-c", "ip route show default 2>/dev/null | head -1; echo ---; cat /proc/net/dev"]
        stdout: StdioCollector { onStreamFinished: {
            const parts = text.split("---\n");
            const route = parts[0] || "", dev = parts[1] || "";
            let want = w.iface;
            if (!want) { const m = route.match(/ dev (\S+)/); want = m ? m[1] : ""; }
            let rxB = 0, txB = 0, name = want, found = false;
            dev.split("\n").slice(2).forEach(l => {
                const i = l.indexOf(":"); if (i < 0) return;
                const n = l.slice(0, i).trim(), f = l.slice(i + 1).trim().split(/\s+/).map(Number);
                if (want ? n === want : n !== "lo") { rxB += f[0]; txB += f[8]; found = true; if (!want) name = "all"; }
            });
            if (!found) return;
            const now = Date.now();
            if (w.last && w.shown === name) {
                const dt = (now - w.last.t) / 1000;
                if (dt > 0.2) {
                    w.rx = Math.max(0, (rxB - w.last.rx) / dt); w.tx = Math.max(0, (txB - w.last.tx) / dt);
                    w.rxH = w.rxH.concat([w.rx]).slice(-w.keep); w.txH = w.txH.concat([w.tx]).slice(-w.keep);
                    w.rxPeak = Math.max(w.rxPeak, w.rx); w.txPeak = Math.max(w.txPeak, w.tx);
                    mini.requestPaint(); big.requestPaint();
                }
            }
            w.last = { t: now, rx: rxB, tx: txB }; w.shown = name; w.rxTotal = rxB; w.txTotal = txB;
        } }
    }
    Process { id: ipp; command: ["sh", "-c", "ip -4 -o addr show dev " + (w.shown && w.shown !== "all" ? w.shown : "lo") + " | awk '{print $4}' | head -1"]
        stdout: StdioCollector { onStreamFinished: w.ip = text.trim() } }

    // ---- paint a smooth filled line chart ----
    function paintLine(c, data, color, width, height, top, fill) {
        if (data.length < 2) return;
        const st = width / (w.keep - 1), off = (w.keep - data.length) * st;
        const y = v => height - Math.min(1, v / top) * (height - 2) - 1;
        c.beginPath(); c.moveTo(off, y(data[0]));
        for (let i = 1; i < data.length; i++) {
            const x0 = off + (i - 1) * st, x1 = off + i * st, mx = (x0 + x1) / 2;
            c.bezierCurveTo(mx, y(data[i - 1]), mx, y(data[i]), x1, y(data[i]));
        }
        c.strokeStyle = color; c.lineWidth = 1.8; c.lineJoin = "round"; c.stroke();
        if (fill) {
            c.lineTo(off + (data.length - 1) * st, height); c.lineTo(off, height); c.closePath();
            const g = c.createLinearGradient(0, 0, 0, height);
            g.addColorStop(0, Qt.rgba(Qt.color(color).r, Qt.color(color).g, Qt.color(color).b, 0.28));
            g.addColorStop(1, Qt.rgba(Qt.color(color).r, Qt.color(color).g, Qt.color(color).b, 0));
            c.fillStyle = g; c.fill();
        }
    }
    readonly property real scaleTop: Math.max(20000, Math.max.apply(null, rxH.concat(txH).concat([1])) * 1.15)

    // ---- the tile ----
    Item {
        anchors.fill: parent
        Row { x: 14; y: 8; spacing: 4
            Icon { name: "arrow_downward"; size: 14; color: w.downC; anchors.verticalCenter: parent.verticalCenter }
            Text { text: w.fmt(w.rx); color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter } }
        Row { anchors { right: parent.right; rightMargin: 14 } y: 8; spacing: 4
            Text { text: w.fmt(w.tx); color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
            Icon { name: "arrow_upward"; size: 14; color: w.upC; anchors.verticalCenter: parent.verticalCenter } }
        Canvas { id: mini; x: 12; y: 30; width: parent.width - 24; height: 14
            onPaint: { const c = getContext("2d"); c.reset(); w.paintLine(c, w.rxH, w.downC, width, height, w.scaleTop, false); } }
    }

    // ---- dropdown ----
    Popover {
        id: pop
        target: w
        panelWidth: 360
        panelHeight: 330
        Column {
            anchors { fill: parent; margins: 16 }
            spacing: 12
            Row { width: parent.width; height: 26
                Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width - chip.width - 8; text: "Network"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Bold }
                Rectangle { id: chip; anchors.verticalCenter: parent.verticalCenter; height: 22; width: ct.implicitWidth + 20; radius: 11; color: Qt.rgba(1, 1, 1, 0.09)
                    Text { id: ct; textFormat: Text.PlainText; anchors.centerIn: parent; text: (w.shown || "—") + (w.ip ? "  ·  " + w.ip : ""); color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 } } }
            Rectangle {
                width: parent.width; height: 120; radius: 14; color: Qt.rgba(1, 1, 1, 0.05); clip: true
                Repeater { model: 3   // faint grid
                    delegate: Rectangle { required property int index; width: parent.width; height: 1; y: (index + 1) * parent.height / 4; color: Qt.rgba(1, 1, 1, 0.06) } }
                Canvas { id: big; anchors { fill: parent; margins: 8 }
                    onPaint: { const c = getContext("2d"); c.reset(); w.paintLine(c, w.txH, w.upC, width, height, w.scaleTop, true); w.paintLine(c, w.rxH, w.downC, width, height, w.scaleTop, true); } }
                Text { anchors { right: parent.right; top: parent.top; margins: 8 } text: w.fmt(w.scaleTop); color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10 }
                Text { anchors { left: parent.left; bottom: parent.bottom; margins: 8 } text: "last 60 s"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10 }
            }
            Row { width: parent.width; spacing: 8
                Repeater {
                    model: [ { l: "Download", v: w.fmt(w.rx), s: "peak " + w.fmt(w.rxPeak), c: w.downC, i: "arrow_downward" },
                             { l: "Upload", v: w.fmt(w.tx), s: "peak " + w.fmt(w.txPeak), c: w.upC, i: "arrow_upward" } ]
                    delegate: Rectangle { required property var modelData
                        width: (parent.width - 8) / 2; height: 64; radius: 14; color: Theme.tileFill
                        Row { x: 12; y: 10; spacing: 6
                            Icon { name: modelData.i; size: 15; color: modelData.c; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: modelData.l; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter } }
                        Text { x: 12; y: 28; text: modelData.v; color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold }
                        Text { x: 12; y: 49; text: modelData.s; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10 }
                    }
                }
            }
            Row { width: parent.width; spacing: 8
                Repeater {
                    model: [ { l: "Received since boot", v: w.fmtBytes(w.rxTotal) }, { l: "Sent since boot", v: w.fmtBytes(w.txTotal) } ]
                    delegate: Rectangle { required property var modelData
                        width: (parent.width - 8) / 2; height: 44; radius: 12; color: Theme.tileFill
                        Column { anchors.centerIn: parent
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.v; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.l; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 9 } }
                    }
                }
            }
        }
    }
}
