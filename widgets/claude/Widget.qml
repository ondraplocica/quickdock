import QtQuick
import Quickshell.Io
import "../../core"

Tile {
    id: w
    implicitWidth: row.implicitWidth + 28
    property var d: ({})
    property bool ok: d.FIVE_HOUR_UTIL !== undefined
    readonly property real five: parseFloat(d.FIVE_HOUR_UTIL || 0)
    readonly property real seven: parseFloat(d.SEVEN_DAY_UTIL || 0)
    readonly property var daily: (d.DAILY || "0,0,0,0,0,0,0").split(",").map(Number)
    readonly property var dailyCost: (d.DAILY_COSTS || "0,0,0,0,0,0,0").split(",").map(Number)
    function toggle() { pop.open = !pop.open; }
    onClicked: toggle()
    function tint(v) { return v > 85 ? Theme.bad : (v > 60 ? Theme.warn : Theme.accent); }
    function until(iso) {
        if (!iso) return "";
        const m = Math.max(0, Math.round((new Date(iso).getTime() - Date.now()) / 60000));
        const dd = Math.floor(m / 1440), h = Math.floor(m % 1440 / 60);
        return "resets in " + (dd ? dd + "d " : "") + (h ? h + "h " : "") + (m % 60) + "m";
    }
    function tok(n) { return n >= 1e9 ? (n / 1e9).toFixed(1) + "B" : (n >= 1e6 ? (n / 1e6).toFixed(1) + "M" : (n >= 1e3 ? Math.round(n / 1e3) + "k" : n)); }

    Timer { interval: 120000; running: true; repeat: true; triggeredOnStart: true; onTriggered: proc.running = true }
    Process {
        id: proc
        command: ["bash", String(Qt.resolvedUrl("get-claude-usage")).replace("file://", "")]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {};
                text.trim().split("\n").forEach(l => { const i = l.indexOf("="); if (i > 0) o[l.slice(0, i)] = l.slice(i + 1); });
                w.d = o;
            }
        }
    }

    Row {
        id: row
        anchors.centerIn: parent; spacing: 8
        Item { width: 30; height: 30; anchors.verticalCenter: parent.verticalCenter
            Ring { anchors.fill: parent; size: 30; thickness: 3.5; value: w.five / 100; fill: w.tint(w.five) }
            Image { anchors.centerIn: parent; width: 14; height: 14; source: "claude.svg"; sourceSize: Qt.size(56, 56); smooth: true; mipmap: true } }
        Text { anchors.verticalCenter: parent.verticalCenter; text: w.ok ? Math.round(w.five) + "%" : "--"
            color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold }
    }

    Popover {
        id: pop
        target: w
        panelWidth: 360
        panelHeight: 400
        Column {
            id: card
            anchors { fill: parent; margins: 16 }
            spacing: 14
            Row { spacing: 8
                Text { text: "Claude usage"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
                Rectangle { height: 20; width: pl.implicitWidth + 14; radius: 10; color: Theme.tileFill; anchors.verticalCenter: parent.verticalCenter
                    Text { id: pl; anchors.centerIn: parent; text: w.d.SUBSCRIPTION_TYPE || ""; color: Theme.accent; font.family: Theme.font; font.pixelSize: 10; font.capitalization: Font.AllUppercase } } }

            Repeater {
                model: [ { l: "5-hour limit", v: w.five, r: w.d.FIVE_HOUR_RESET }, { l: "7-day limit", v: w.seven, r: w.d.SEVEN_DAY_RESET } ]
                delegate: Column {
                    required property var modelData
                    width: card.width; spacing: 5
                    Row { width: parent.width
                        Text { text: modelData.l; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; width: parent.width / 2 }
                        Text { text: Math.round(modelData.v) + "%  ·  " + w.until(modelData.r); color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11
                            width: parent.width / 2; horizontalAlignment: Text.AlignRight } }
                    Rectangle { width: parent.width; height: 8; radius: 4; color: Theme.tileFill
                        Rectangle { height: 8; radius: 4; color: w.tint(modelData.v)
                            width: pop.open ? Math.max(8, parent.width * modelData.v / 100) : 0
                            Behavior on width { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } } } }
                }
            }

            Row {   // costs
                spacing: 8
                Repeater {
                    model: [ { l: "Today", v: w.d.TODAY_COST }, { l: "Week", v: w.d.WEEK_COST }, { l: "Month", v: w.d.MONTH_COST } ]
                    delegate: Rectangle {
                        required property var modelData
                        width: (card.width - 16) / 3; height: 54; radius: 14; color: Theme.tileFill
                        Column { anchors.centerIn: parent
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "$" + (modelData.v || "0"); color: Theme.text
                                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.l + " (est.)"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10 } }
                    }
                }
            }

            Text { text: "Tokens, last 7 days · " + w.tok(parseFloat(w.d.WEEK_TOKENS || 0)) + " total"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 }
            Row {   // daily bars
                spacing: 8; height: 74
                readonly property real mx: Math.max.apply(null, w.daily.concat([1]))
                Repeater {
                    model: w.daily
                    delegate: Item {
                        required property real modelData
                        required property int index
                        width: (card.width - 48) / 7; height: 74
                        Rectangle { anchors { bottom: lbl.top; bottomMargin: 4; horizontalCenter: parent.horizontalCenter }
                            width: parent.width; radius: 5; color: index === w.daily.length - 1 || modelData === Math.max.apply(null, w.daily) ? Theme.accent : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.4)
                            height: pop.open ? Math.max(3, (parent.height - 18) * modelData / parent.parent.mx) : 0
                            Behavior on height { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } } }
                        Text { id: lbl; anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                            text: ["M", "T", "W", "T", "F", "S", "S"][index]; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10 }
                    }
                }
            }
        }
    }
}
