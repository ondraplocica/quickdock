import QtQuick
import Quickshell.Io
import "../../core"

// Template widget. Copy this folder (widgets/example -> widgets/mywidget), rename the id in manifest.json,
// add "mywidget" to "widgets" in config/dock.json (or use the bar builder) and edit this file.
//
// What it shows:
//   * Tile is the base card; your settings live in dock.json -> widgetConfig.<id> (`config`, or live via Dock.cfg)
//   * Process runs a command and hands you its output
//   * Popover is the dropdown that opens next to the tile
//   * Dock.saveWidget(id, {...}) saves a setting back to dock.json
//   * Theme.* are the colours / sizes, never hard-code them
Tile {
    id: w
    implicitWidth: row.implicitWidth + 28                 // width of the tile; height is fixed by the dock

    property string uptime: "…"
    // `config` is handed over once when the widget loads. For a setting you change at runtime, read it live from
    // Dock.cfg instead so the tile follows the change right away:
    readonly property var live: (Dock.cfg.widgetConfig || {})[w.instanceId || "example"] || ({})
    readonly property string label: live.label ?? "Uptime"      // widgetConfig.example.label, with a default
    readonly property int clicks: live.clicks ?? 0

    onClicked: pop.open = !pop.open

    // run a command every minute and keep the output
    Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: proc.running = true }
    Process {
        id: proc
        command: ["uptime", "-p"]
        stdout: StdioCollector { onStreamFinished: w.uptime = text.trim().replace(/^up /, "") }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8
        Icon { anchors.verticalCenter: parent.verticalCenter; name: "schedule"; size: 20; color: Theme.accent }
        Column { anchors.verticalCenter: parent.verticalCenter
            Text { text: w.uptime; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
            Text { text: w.label; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 9 } }
    }

    Popover {
        id: pop
        target: w                       // opens next to this tile
        panelWidth: 260                 // laid out at 1x; the dock scales it with "Dropdown scale"
        panelHeight: 120
        Column {
            anchors { fill: parent; margins: 16 }
            spacing: 10
            Text { text: "Hello from a widget"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
            Text { text: "Clicked " + w.clicks + " times (saved in dock.json)"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
            Rectangle {
                width: 110; height: 30; radius: 15
                color: hit.containsMouse ? Theme.tileFillHover : Qt.rgba(1, 1, 1, 0.08)
                Text { anchors.centerIn: parent; text: "Count"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                MouseArea { id: hit; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: Dock.saveWidget(w.instanceId || "example", { clicks: w.clicks + 1 }) }
            }
        }
    }
}
