import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"

Tile {
    id: w
    implicitWidth: row.implicitWidth + 26
    property var g: null
    // safe view of the data so bindings never read through null while it loads
    readonly property var d: g ? g : ({ days: [], prs: [], streak: 0, best: 0, prTotal: 0, reviewRequested: 0, today: 0, total: 0, login: "" })
    property string state: "loading"      // loading | ok | auth | error
    property real lastFetch: 0
    readonly property var days: g ? g.days : []
    readonly property int maxCount: Math.max(1, Math.max.apply(null, days.map(d => d.count).concat([1])))
    function toggle() { pop.open = !pop.open; if (pop.open && Date.now() - lastFetch > 120000) proc.running = true; }
    onClicked: toggle()
    function shade(c) {
        if (c <= 0) return Qt.rgba(1, 1, 1, 0.07);
        const t = Math.min(1, c / Math.max(4, w.maxCount));
        const a = t < 0.25 ? 0.35 : (t < 0.5 ? 0.55 : (t < 0.75 ? 0.78 : 1));
        return Qt.rgba(Theme.good.r, Theme.good.g, Theme.good.b, a);
    }
    function ago(iso) {
        const s = (Date.now() - new Date(iso).getTime()) / 1000;
        if (s < 3600) return Math.max(1, Math.round(s / 60)) + "m"; if (s < 86400) return Math.round(s / 3600) + "h";
        return Math.round(s / 86400) + "d";
    }

    Timer { interval: 900000; running: true; repeat: true; triggeredOnStart: true; onTriggered: proc.running = true }
    Process {
        id: proc
        command: ["python3", "-I", String(Qt.resolvedUrl("gh.py")).replace("file://", "")]
        stdout: StdioCollector { onStreamFinished: {
            try {
                const r = JSON.parse(text);
                if (r.ok) { w.g = r; w.state = "ok"; w.lastFetch = Date.now(); } else w.state = r.error === "auth" ? "auth" : "error";
            } catch (e) { w.state = "error"; } } }
    }

    Row {
        id: row
        anchors.centerIn: parent; spacing: 9
        Row {   // last 7 days as a tiny strip
            anchors.verticalCenter: parent.verticalCenter; spacing: 2
            Repeater { model: w.days.slice(-7)
                delegate: Rectangle { required property var modelData; width: 6; height: 18; radius: 2; color: w.shade(modelData.count)
                    Behavior on color { ColorAnimation { duration: 300 } } } }
        }
        Column { anchors.verticalCenter: parent.verticalCenter
            Text { text: w.state === "ok" ? w.d.today : "--"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold }
            Text { text: "today"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 9 } }
    }

    Popover {
        id: pop
        target: w
        panelWidth: 420
        panelHeight: w.state === "ok" ? 250 + Math.max(1, w.d.prs.length) * 40 + (w.d.reviewRequested > 0 ? 0 : 0) : 130
        Text { visible: w.state !== "ok"; anchors.centerIn: parent; width: parent.width - 40; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
            text: w.state === "auth" ? "Sign in with `gh auth login` in a terminal." : (w.state === "loading" ? "Loading…" : "Couldn't reach GitHub.") }
        Column {
            id: card
            visible: w.state === "ok"
            anchors { fill: parent; margins: 16 }
            spacing: 12
            Row { spacing: 10
                Text { text: w.state === "ok" ? w.d.login : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter }
                Text { text: w.state === "ok" ? w.d.total + " contributions in the last year" : ""; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter } }

            Item {   // heatmap: 26 weeks x 7 days, columns = weeks
                width: card.width; height: 7 * 13
                Repeater {
                    model: w.days
                    delegate: Rectangle {
                        id: hc
                        required property var modelData
                        required property int index
                        readonly property int offset: (new Date(w.days[0].date + "T12:00:00").getDay() + 6) % 7   // Monday-first row of day 0
                        readonly property int slot: index + offset
                        x: Math.floor(slot / 7) * 13 + (card.width - 27 * 13) / 2
                        y: (slot % 7) * 13
                        width: 11; height: 11; radius: Theme.square ? 2 : 3
                        color: w.shade(modelData.count)
                        opacity: 0
                        Component.onCompleted: fade.start()
                        SequentialAnimation { id: fade
                            PauseAnimation { duration: Math.floor(hc.slot / 7) * 18 }
                            NumberAnimation { target: hc; property: "opacity"; to: 1; duration: 200 } }
                        MouseArea { id: hm; anchors.fill: parent; hoverEnabled: true }
                        Rectangle { visible: hm.containsMouse; z: 5; x: -30; y: -26; width: tl.implicitWidth + 14; height: 20; radius: 10; color: Theme.popFill; border.width: 1; border.color: Theme.hairline
                            Text { id: tl; anchors.centerIn: parent; text: modelData.count + " on " + modelData.date.slice(5); color: Theme.text; font.family: Theme.font; font.pixelSize: 10 } }
                    }
                }
            }
            Row { spacing: 8
                Repeater {
                    model: [ { l: "Current streak", v: w.d.streak + " d" }, { l: "Best streak", v: w.d.best + " d" },
                             { l: "Open PRs", v: w.d.prTotal }, { l: "Review requested", v: w.d.reviewRequested } ]
                    delegate: Rectangle { required property var modelData
                        width: (card.width - 24) / 4; height: 50; radius: 12; color: Theme.tileFill
                        Column { anchors.centerIn: parent
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.v; color: modelData.l === "Review requested" && modelData.v > 0 ? Theme.warn : Theme.text
                                font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.l; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 9 } }
                    }
                }
            }
            Text { text: w.d.prs.length ? "Your open pull requests" : "No open pull requests"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 }
            Repeater {
                model: w.g ? w.d.prs : []
                delegate: Rectangle {
                    required property var modelData
                    width: card.width; height: 36; radius: 10
                    color: pm.containsMouse ? Theme.tileFillHover : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Icon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: modelData.draft ? "edit_note" : "merge_type"; size: 18; color: modelData.draft ? Theme.textDim : Theme.accent }
                    Column { x: 36; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 80
                        Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: modelData.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                        Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: modelData.repo; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10 } }
                    Text { anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } text: w.ago(modelData.updated); color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 }
                    MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { Quickshell.execDetached(["xdg-open", modelData.url]); pop.open = false; } }
                }
            }
        }
    }
}
