pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Widgets you keep OUTSIDE the repo, so the repo can stay a clean public project and your own stuff lives in your config:
//   ~/.config/quickdock/widgets/<id>/{manifest.json, Widget.qml [, Settings.qml]}      ($XDG_CONFIG_HOME is honoured)
// A user widget with the same id as a built-in one replaces it. Inside a user widget import the shared types with
//   import "root:/core"        (built-in widgets use "../../core"; root:/ is the dock's own folder)
Singleton {
    id: u
    readonly property string dir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/quickdock/widgets"
    property bool settled: false         // scan finished (or timed out): ids can be resolved now
    property var ids: []                 // folders in the user dir that contain a Widget.qml

    // One-shot scan. (Not FolderListModel: for a missing folder it silently lists the working directory instead.)
    Process {
        id: scan
        running: true
        command: ["sh", "-c", 'for d in "$1"/*/; do [ -f "${d}Widget.qml" ] && basename "$d"; done; true', "sh", u.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                u.ids = text.split("\n").map(x => x.trim()).filter(x => /^[A-Za-z0-9_-]+$/.test(x));
                u.settled = true;
            }
        }
    }
    Timer { interval: 1500; running: true; onTriggered: u.settled = true }   // never block the dock on a stuck scan

    function has(id) { return ids.indexOf(id) >= 0; }
    // Loader source for widget <id>: your copy if there is one, else the built-in (relative to shell.qml)
    function source(id) { return has(id) ? "file://" + dir + "/" + id + "/Widget.qml" : "widgets/" + id + "/Widget.qml"; }
    function settingsSource(id) { return has(id) ? "file://" + dir + "/" + id + "/Settings.qml" : String(Qt.resolvedUrl("../widgets/" + id + "/Settings.qml")); }
}
