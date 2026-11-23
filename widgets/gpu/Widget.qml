import QtQuick
import Quickshell.Io
import "../../core"

Tile {
    id: w
    interactive: false
    implicitWidth: 92
    property real temp: 0
    property real util: 0
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: p.running = true }
    Process { id: p; command: ["nvidia-smi", "--query-gpu=temperature.gpu,utilization.gpu", "--format=csv,noheader,nounits"]
        stdout: StdioCollector { onStreamFinished: { const f = text.trim().split(/,\s*/); if (f.length >= 2) { w.temp = parseFloat(f[0]); w.util = parseFloat(f[1]); } } } }
    property color tint: temp > 85 ? Theme.bad : (temp > 75 ? Theme.warn : Theme.good)
    Behavior on tint { ColorAnimation { duration: 500 } }
    Column { anchors.centerIn: parent
        Row { spacing: 5; anchors.horizontalCenter: parent.horizontalCenter
            Text { text: "GPU"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10; anchors.baseline: t1.baseline }
            Text { id: t1; text: Math.round(w.temp) + "°"; color: w.tint; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Bold } }
        Rectangle { width: 56; height: 4; radius: 2; color: Theme.tileFill; anchors.horizontalCenter: parent.horizontalCenter
            Rectangle { height: 4; radius: 2; color: w.tint; width: Math.max(4, parent.width * w.util / 100)
                Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } } } }
    }
}
