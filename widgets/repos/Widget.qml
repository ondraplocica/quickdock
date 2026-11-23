import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"

// Git repositories at a glance: how many need attention (uncommitted changes, unpushed or unpulled commits).
// widgetConfig.repos = {
//   "roots": ["~"],                  // folders whose direct sub-folders are scanned for repositories (default ~)
//   "repos": ["~/work/thing"],       // extra repositories by path
//   "exclude": ["Downloads"],        // folder names to skip
//   "worktrees": false,              // true: also list linked git worktrees as separate repos
//   "open": ["code", "{path}"]       // optional: what a click runs (default: open the folder)
// }
// Read-only (git status). The "Fetch all" button is the only thing that touches the network.
Tile {
    id: w
    implicitWidth: row.implicitWidth + 24
    readonly property string home: Quickshell.env("HOME")
    readonly property var gcfg: ({ roots: config.roots, repos: config.repos, exclude: config.exclude, worktrees: config.worktrees })
    property var repos: []
    property bool loaded: false
    property bool busy: false
    readonly property var attention: repos.filter(r => !r.error && (r.changed > 0 || r.untracked > 0 || r.ahead > 0 || r.behind > 0))
    readonly property var clean: repos.filter(r => !r.error && !(r.changed > 0 || r.untracked > 0 || r.ahead > 0 || r.behind > 0))
    readonly property var broken: repos.filter(r => r.error)
    readonly property bool unpushed: repos.some(r => !r.error && r.ahead > 0)
    function toggle() { pop.open = !pop.open; }
    onClicked: toggle()
    function refresh() { if (!st.running && !fe.running) st.running = true; }
    function fetchAll() { if (fe.running || st.running) return; busy = true; fe.running = true; }
    function pretty(p) { return p.indexOf(home) === 0 ? "~" + p.slice(home.length) : p; }
    function openRepo(path) {
        if (Array.isArray(config.open) && config.open.length) Quickshell.execDetached(config.open.map(a => String(a).split("{path}").join(path)));
        else Quickshell.execDetached(["xdg-open", path]);
    }

    Timer { interval: 180000; running: true; repeat: true; triggeredOnStart: true; onTriggered: w.refresh() }
    Process {
        id: st
        command: ["python3", "-I", String(Qt.resolvedUrl("repos.py")).replace("file://", ""), "status", JSON.stringify(w.gcfg)]
        stdout: StdioCollector { onStreamFinished: { try { const r = JSON.parse(text); if (r.ok) w.repos = r.repos; } catch (e) {} w.loaded = true; } }
    }
    Process {
        id: fe
        command: ["python3", "-I", String(Qt.resolvedUrl("repos.py")).replace("file://", ""), "fetch", JSON.stringify(w.gcfg)]
        stdout: StdioCollector { onStreamFinished: { try { const r = JSON.parse(text); if (r.ok) w.repos = r.repos; } catch (e) {} w.busy = false; w.loaded = true; } }
        onExited: w.busy = false
    }

    Row {
        id: row
        anchors.centerIn: parent; spacing: 8
        Icon { anchors.verticalCenter: parent.verticalCenter; name: "account_tree"; size: 22
            color: w.attention.length === 0 ? Theme.text : (w.unpushed ? Theme.warn : Theme.accent) }
        Text { anchors.verticalCenter: parent.verticalCenter; visible: w.loaded
            text: w.attention.length === 0 ? "✓" : w.attention.length
            color: w.attention.length === 0 ? Theme.good : (w.unpushed ? Theme.warn : Theme.text)
            font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold }
    }

    Popover {
        id: pop
        target: w
        panelWidth: 380
        panelHeight: 112 + Math.min(w.attention.length, 7) * 56 + (w.attention.length > 7 ? 24 : 0) + (w.attention.length === 0 ? 40 : 0) + (w.broken.length > 0 ? 28 : 0)
        onOpenChanged: if (open) w.refresh()
        Column { anchors { fill: parent; margins: 16 } spacing: 10
            Row { width: parent.width
                Text { width: parent.width - 150; anchors.verticalCenter: parent.verticalCenter; text: "Git repositories"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
                Row { spacing: 6; anchors.verticalCenter: parent.verticalCenter
                    Rectangle { height: 26; width: rt.implicitWidth + 20; radius: 13; color: rfm.containsMouse ? Theme.tileFillHover : Qt.rgba(1, 1, 1, 0.08)
                        Text { id: rt; anchors.centerIn: parent; text: "Refresh"; color: Theme.text; font.family: Theme.font; font.pixelSize: 10 }
                        MouseArea { id: rfm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.refresh() } }
                    Rectangle { height: 26; width: ft.implicitWidth + 20; radius: 13; opacity: w.busy ? 0.6 : 1; color: ffm.containsMouse ? Theme.tileFillHover : Qt.rgba(1, 1, 1, 0.08)
                        Text { id: ft; anchors.centerIn: parent; text: w.busy ? "Fetching…" : "Fetch all"; color: Theme.text; font.family: Theme.font; font.pixelSize: 10 }
                        MouseArea { id: ffm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.fetchAll() } } } }
            Text { width: parent.width; textFormat: Text.PlainText; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11
                text: w.attention.length + " need attention · " + w.clean.length + " clean" + (w.broken.length ? " · " + w.broken.length + " unreadable" : "") }
            Text { visible: w.loaded && w.attention.length === 0; width: parent.width; horizontalAlignment: Text.AlignHCenter; height: 30; verticalAlignment: Text.AlignVCenter
                color: Theme.good; font.family: Theme.font; font.pixelSize: 12; text: "Everything is committed and in sync" }
            Column { width: parent.width; spacing: 4
                Repeater { model: w.attention.slice(0, 7)
                    delegate: Rectangle {
                        id: rr
                        required property var modelData
                        width: parent.width; height: 52; radius: 12
                        color: rm.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : Theme.tileFill
                        Column { x: 12; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 24; spacing: 3
                            Row { width: parent.width; spacing: 8
                                Text { textFormat: Text.PlainText; text: rr.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight; width: Math.min(implicitWidth, parent.width - 120) }
                                Text { textFormat: Text.PlainText; text: rr.modelData.branch; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11; anchors.baseline: parent.children[0].baseline } }
                            Row { spacing: 10
                                Text { visible: rr.modelData.ahead > 0; text: "↑ " + rr.modelData.ahead + " to push"; color: Theme.warn; font.family: Theme.font; font.pixelSize: 11 }
                                Text { visible: rr.modelData.behind > 0; text: "↓ " + rr.modelData.behind + " to pull"; color: Theme.accent; font.family: Theme.font; font.pixelSize: 11 }
                                Text { visible: rr.modelData.changed > 0; text: "● " + rr.modelData.changed + " changed"; color: Theme.text; font.family: Theme.font; font.pixelSize: 11 }
                                Text { visible: rr.modelData.untracked > 0; text: "+ " + rr.modelData.untracked + " new"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 }
                                Text { visible: !rr.modelData.upstream && rr.modelData.branch !== "" && rr.modelData.ahead === 0 && rr.modelData.changed === 0 && rr.modelData.untracked === 0; text: "no upstream"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 } } }
                        MouseArea { id: rm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.openRepo(rr.modelData.path) }
                    } }
            }
            Text { visible: w.attention.length > 7; width: parent.width; horizontalAlignment: Text.AlignHCenter; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10
                text: "+" + (w.attention.length - 7) + " more" }
            Text { visible: w.broken.length > 0; width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10
                text: "Unreadable: " + w.broken.map(r => r.name).join(", ") }
        }
    }
}
