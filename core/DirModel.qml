import QtQuick
import Qt.labs.folderlistmodel
import Quickshell.Io

// A folder listing that is EMPTY when the folder does not exist. (A bare FolderListModel silently lists the working
// directory, i.e. the dock's own folder, for a missing path.)
//   DirModel { id: files; path: "/home/me/Videos"; nameFilters: ["*.mp4"] }
//   Repeater { model: files.items; delegate: ... }      files.count / files.ready / files.recheck()
Item {
    id: d
    property string path: ""                 // absolute folder, no file:// prefix
    property var nameFilters: []
    property bool showDirs: false
    property bool exists: false
    readonly property int count: exists ? m.count : 0
    readonly property bool ready: exists && m.status === FolderListModel.Ready
    readonly property var items: exists ? m : null   // use as a model; null = no rows
    function recheck() { chk.running = false; chk.running = true; }
    onPathChanged: recheck()
    Component.onCompleted: recheck()

    Process { id: chk; command: ["test", "-d", d.path]; onExited: code => d.exists = (code === 0 && d.path !== "") }
    FolderListModel {
        id: m
        folder: d.exists ? "file://" + d.path : ""
        nameFilters: d.nameFilters
        showDirs: d.showDirs
        showDotAndDotDot: false
        showHidden: false
        sortField: FolderListModel.Time          // newest first (Qt's default order for Time)
        sortReversed: false
    }
}
