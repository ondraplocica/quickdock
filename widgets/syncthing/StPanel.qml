import QtQuick
import "../../core"

// Dropdown content of the syncthing widget. `host` is the widget (state).
Item {
    id: p
    property var host
    readonly property var folders: (host && host.ok) ? (host.st.folders || []) : []
    readonly property var devices: (host && host.ok) ? (host.st.devices || []) : []

    function folderText(f) {
        if (f.paused) return "Paused";
        if (f.errors > 0) return f.errors + (f.errors === 1 ? " item failed to sync" : " items failed to sync");
        if (f.state === "idle") return f.needBytes > 0 ? "Out of sync · " + p.host.bytes(f.needBytes) + " to go" : "Up to date";
        if (f.state.indexOf("sync") === 0) return "Syncing · " + f.pct + "%" + (f.needBytes > 0 ? " · " + p.host.bytes(f.needBytes) + " left" : "");
        if (f.state.indexOf("scan") === 0) return "Scanning";
        if (f.state === "error") return "Error";
        return f.state;
    }
    function folderColor(f) {
        if (f.paused) return Theme.textDim;
        if (f.errors > 0 || f.state === "error") return Theme.bad;
        if (f.state === "idle") return f.needBytes > 0 ? Theme.warn : Theme.good;
        return Theme.accent;
    }

    Column {
        anchors.fill: parent
        spacing: 10

        Row { width: parent.width; height: 26
            Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width - chip.width - 8; text: "Syncthing"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Bold }
            Rectangle { id: chip; anchors.verticalCenter: parent.verticalCenter; height: 22; width: ct.implicitWidth + 20; radius: 11
                color: Qt.rgba(p.host.stateColor.r, p.host.stateColor.g, p.host.stateColor.b, 0.16)
                Text { id: ct; anchors.centerIn: parent; text: p.host.label; color: p.host.stateColor; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold } } }

        Text { visible: !p.host.ok; width: parent.width; wrapMode: Text.WordWrap
            text: p.host.st.error === "noconfig" ? "No Syncthing config found." : (p.host.st.error === "tls" ? "The Syncthing GUI uses HTTPS; only plain loopback HTTP is supported." : "Syncthing isn't running (systemctl --user start syncthing).")
            color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }

        Text { visible: p.host.ok; text: "Folders"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium; leftPadding: 2 }
        Repeater {
            model: p.folders
            delegate: Rectangle { required property var modelData
                width: parent.width; height: 52; radius: 12; color: Theme.tileFill
                Rectangle { x: 12; y: 12; width: 8; height: 8; radius: 4; color: p.folderColor(modelData) }
                Text { textFormat: Text.PlainText; x: 30; y: 7; width: parent.width - 42; elide: Text.ElideRight; text: modelData.label
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                Text { textFormat: Text.PlainText; x: 30; y: 25; width: parent.width - 42; elide: Text.ElideRight; text: p.folderText(modelData)
                    color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 }
                Rectangle { x: 12; y: 43; width: parent.width - 24; height: 3; radius: 1.5; color: Qt.rgba(1, 1, 1, 0.10)
                    Rectangle { width: parent.width * Math.max(0, Math.min(100, modelData.pct)) / 100; height: parent.height; radius: 1.5; color: p.folderColor(modelData)
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } } } }
            }
        }

        Text { visible: p.host.ok && p.devices.length > 0; text: "Devices"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium; leftPadding: 2 }
        Repeater {
            model: p.devices
            delegate: Rectangle { required property var modelData
                width: parent.width; height: 40; radius: 12; color: Theme.tileFill
                Rectangle { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4
                    color: modelData.paused ? Theme.textDim : (modelData.connected ? Theme.good : Theme.warn) }
                Text { textFormat: Text.PlainText; x: 30; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 42 - st2.implicitWidth; elide: Text.ElideRight; text: modelData.name
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                Text { id: st2; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    text: modelData.paused ? "Paused" : (modelData.connected ? "Connected" : "Seen " + p.host.ago(modelData.lastSeen))
                    color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 }
            }
        }

        Rectangle { visible: p.host.ok; width: parent.width; height: 32; radius: 10; color: gh.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.07)
            Row { anchors.centerIn: parent; spacing: 6
                Icon { name: "open_in_new"; size: 15; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "Open Syncthing GUI"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter } }
            MouseArea { id: gh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: p.host.openGui() } }
    }
}
