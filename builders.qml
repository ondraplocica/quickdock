import QtQuick
import Quickshell
import Quickshell.Io
import "core"

// Stand-alone launcher for the two builder windows, independent of the running dock process:
//   BUILDER=bar|qs quickshell -p ~/quickdock/builders.qml        (or scripts/open-builder.sh bar|qs)
// It reads and writes the same config/dock.json, so the live dock picks up Apply through its file watch. Because
// this is a separate process, Dock.closeAll() here cannot reach the live dock's dropdowns: it asks the live dock
// to close them over IPC first (Apply already waits ~450 ms after closeAll before saving). The process exits when
// the builder window is closed.
ShellRoot {
    id: root
    settings.watchFiles: false
    readonly property string repo: String(Qt.resolvedUrl(".")).replace("file://", "").replace(/\/$/, "")
    readonly property bool wantQs: Quickshell.env("BUILDER") === "qs"

    Builder { id: bar; visible: !root.wantQs
        onVisibleChanged: if (!visible && !qs.visible) Qt.quit() }
    QsBuilder { id: qs; visible: root.wantQs
        onVisibleChanged: if (!visible && !bar.visible) Qt.quit() }

    Connections { target: Dock; function onCloseAll() { closeLive.running = true; } }
    // the running dock is the quickshell instance whose config is this repo's shell.qml
    Process { id: closeLive; command: ["quickshell", "ipc", "-p", root.repo + "/shell.qml", "call", "dock", "closeAll"] }
}
