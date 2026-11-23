import QtQuick
import "../../core"

// Dropdown content of the tailscale widget. `w` is the widget (state + actions).
Item {
    id: p
    property var host
    readonly property var peers: (host && host.ok) ? (host.st.peers || []) : []
    readonly property var exits: peers.filter(x => x.exitOption)

    Column {
        anchors.fill: parent
        spacing: 10

        Row { width: parent.width; height: 28
            Column { anchors.verticalCenter: parent.verticalCenter; width: parent.width - sw.width - 8
                Text { text: "Tailscale"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Bold }
                Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; visible: text !== ""
                    text: !p.host.ok ? (p.host.st.error === "missing" ? "tailscale is not installed" : "tailscaled is not running") : (p.host.running ? "Connected" : p.host.st.state)
                    color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10 } }
            Rectangle { id: sw; anchors.verticalCenter: parent.verticalCenter; width: 44; height: 26; radius: 13
                visible: p.host.ok
                color: p.host.running ? Theme.good : Qt.rgba(1, 1, 1, 0.14); opacity: p.host.operator ? 1 : 0.55
                Behavior on color { ColorAnimation { duration: Theme.fast } }
                Rectangle { width: 20; height: 20; radius: 10; y: 3; x: p.host.running ? 21 : 3; color: "white"
                    Behavior on x { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } } }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: p.host.toggleUp() } }
        }

        // one-time setup hint
        Rectangle { visible: p.host.ok && !p.host.operator; width: parent.width; height: hint.implicitHeight + 20; radius: 12
            color: Qt.rgba(1, 0.72, 0.3, 0.12); border.width: 1; border.color: Qt.rgba(1, 0.72, 0.3, 0.35)
            Column { id: hint; x: 12; y: 10; width: parent.width - 24; spacing: 6
                Text { width: parent.width; wrapMode: Text.WordWrap; text: "Connect / exit node need operator rights. Run once in a terminal:"
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 11 }
                Rectangle { width: parent.width; height: 28; radius: 8; color: Qt.rgba(0, 0, 0, 0.35)
                    Text { anchors { left: parent.left; leftMargin: 8; right: cp.left; verticalCenter: parent.verticalCenter } elide: Text.ElideRight
                        text: p.host.fixCmd; color: Theme.warn; font.family: "monospace"; font.pixelSize: 10 }
                    Rectangle { id: cp; anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter } width: 48; height: 20; radius: 10; color: Qt.rgba(1, 1, 1, 0.12)
                        Text { anchors.centerIn: parent; text: "Copy"; color: Theme.text; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.Medium }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: p.host.copy(p.host.fixCmd) } } } } }

        // this node
        Rectangle { visible: p.host.ok; width: parent.width; height: 44; radius: 12; color: Theme.tileFill
            Rectangle { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: p.host.stateColor }
            Column { x: 30; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 42
                Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: p.host.st.self ? p.host.st.self.name + "  (this device)" : ""
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                Text { textFormat: Text.PlainText; text: p.host.st.self ? p.host.st.self.ip : ""; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 } }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: p.host.copy(p.host.st.self.ip) } }

        // exit node chooser header
        Rectangle { visible: p.host.running; width: parent.width; height: 40; radius: 12; color: p.host.exitOpen ? Qt.rgba(1, 1, 1, 0.10) : Theme.tileFill
            Row { x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                Icon { name: "logout"; size: 17; color: p.host.exitNode ? Theme.accent : Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "Exit node"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter } }
            Text { textFormat: Text.PlainText; anchors { right: chev.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                text: p.host.exitNode || "None"; color: p.host.exitNode ? Theme.accent : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
            Icon { id: chev; anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } name: p.host.exitOpen ? "expand_less" : "expand_more"; size: 18; color: Theme.textDim }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: p.host.exitOpen = !p.host.exitOpen } }

        Text { visible: p.host.running; text: p.host.exitOpen ? "Choose exit node" : "Devices  ·  " + p.host.st.online + " / " + p.host.st.total + " online"
            color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium; leftPadding: 2 }

        Flickable {
            visible: p.host.running
            width: parent.width; height: p.height - y - (msgText.visible ? 22 : 0)
            contentHeight: list.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds

            Column { id: list; width: parent.width; spacing: 4
                // exit-node list
                Repeater {
                    model: p.host.exitOpen ? [{ name: "None", ip: "none", online: true, none: true }].concat(p.exits) : []
                    delegate: Rectangle { required property var modelData
                        width: list.width; height: 36; radius: 10
                        color: er.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Theme.tileFill; opacity: modelData.online ? 1 : 0.45
                        Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; size: 16
                            name: (modelData.none ? !p.host.exitNode : modelData.isExit) ? "radio_button_checked" : "radio_button_unchecked"
                            color: (modelData.none ? !p.host.exitNode : modelData.isExit) ? Theme.accent : Theme.textDim }
                        Text { textFormat: Text.PlainText; x: 34; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 44; elide: Text.ElideRight
                            text: modelData.name + (modelData.none || modelData.online ? "" : "  ·  offline"); color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                        MouseArea { id: er; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: modelData.online; onClicked: p.host.setExit(modelData.ip) } }
                }
                // peer list
                Repeater {
                    model: p.host.exitOpen ? [] : p.peers
                    delegate: Rectangle { required property var modelData
                        width: list.width; height: 38; radius: 10
                        color: pr.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                        Rectangle { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: modelData.online ? Theme.good : Qt.rgba(1, 1, 1, 0.25) }
                        Column { x: 28; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 36 - ipT.implicitWidth
                            Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: modelData.name
                                color: modelData.online ? Theme.text : Theme.textDim; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                            Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight
                                text: (modelData.os || "") + (modelData.exitOption ? (modelData.os ? "  ·  " : "") + "exit node" : "") + (modelData.online ? "" : ((modelData.os || modelData.exitOption) ? "  ·  " : "") + p.host.ago(modelData.lastSeen))
                                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10 } }
                        Text { id: ipT; textFormat: Text.PlainText; anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: modelData.ip; color: Theme.textDim; font.family: "monospace"; font.pixelSize: 11 }
                        MouseArea { id: pr; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: p.host.copy(modelData.ip) } }
                }
            }
        }

        Text { id: msgText; visible: p.host.msg !== ""; width: parent.width; elide: Text.ElideRight; text: p.host.msg
            color: Theme.warn; font.family: Theme.font; font.pixelSize: 11 }
    }
}
