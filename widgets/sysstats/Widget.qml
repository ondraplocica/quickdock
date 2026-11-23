import QtQuick
import Quickshell.Io
import "../../core"

Tile {
    id: w
    interactive: false
    implicitWidth: 176
    property real cpu: 0
    property real mem: 0
    property var hist: []
    property var last: null

    Timer { interval: 1500; running: true; repeat: true; triggeredOnStart: true; onTriggered: proc.running = true }
    Process {
        id: proc
        command: ["sh", "-c", "head -1 /proc/stat; grep -E '^(MemTotal|MemAvailable)' /proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                const c = l[0].trim().split(/\s+/).slice(1).map(Number);
                const idle = c[3] + c[4], total = c.reduce((a, b) => a + b, 0);
                if (w.last) {
                    const dt = total - w.last.total, di = idle - w.last.idle;
                    w.cpu = dt > 0 ? 100 * (1 - di / dt) : 0;
                    const h = w.hist.concat([w.cpu]); w.hist = h.slice(-30);
                    spark.requestPaint();
                }
                w.last = { idle: idle, total: total };
                const mt = parseInt(l[1].split(/\s+/)[1]), ma = parseInt(l[2].split(/\s+/)[1]);
                w.mem = 100 * (1 - ma / mt);
            }
        }
    }
    property color tint: Theme.load(cpu)
    Behavior on tint { ColorAnimation { duration: 500 } }

    Column {
        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
        Row { spacing: 5
            Text { text: "CPU"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10; anchors.baseline: c1.baseline }
            Text { id: c1; text: Math.round(w.cpu) + "%"; color: w.tint; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold } }
        Row { spacing: 5
            Text { text: "RAM"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10; anchors.baseline: c2.baseline }
            Text { id: c2; text: Math.round(w.mem) + "%"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 } }
    }
    Canvas {
        id: spark
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        width: 70; height: parent.height - 20
        onPaint: {
            const c = getContext("2d"); c.reset();
            const h = w.hist; if (h.length < 2) return;
            const st = width / (h.length - 1);
            const y = v => height - Math.max(0, Math.min(100, v)) / 100 * (height - 2) - 1;
            c.beginPath(); c.moveTo(0, y(h[0]));
            for (let i = 1; i < h.length; i++) { const mx = ((i - 1) + i) * st / 2; c.bezierCurveTo(mx, y(h[i-1]), mx, y(h[i]), i * st, y(h[i])); }
            c.strokeStyle = w.tint; c.lineWidth = 1.8; c.stroke();
            c.lineTo(width, height); c.lineTo(0, height); c.closePath();
            const g = c.createLinearGradient(0, 0, 0, height);
            g.addColorStop(0, Qt.rgba(w.tint.r, w.tint.g, w.tint.b, 0.35)); g.addColorStop(1, Qt.rgba(w.tint.r, w.tint.g, w.tint.b, 0));
            c.fillStyle = g; c.fill();
        }
    }
}
