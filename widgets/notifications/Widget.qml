import QtQuick
import Quickshell
import "../../core"

// Notification bell: a dropdown right under the icon with the recent notifications (from Notifs), do-not-disturb and
// clear-all. DMS remains the notification daemon (popups, sounds); the old DMS centre is no longer opened from here.
Tile {
    id: w
    implicitWidth: Theme.tileHeight
    function toggle() { pop.open = !pop.open; }
    onClicked: toggle()

    Icon { anchors.centerIn: parent; name: Notifs.unread > 0 ? "notifications_unread" : "notifications"; size: 24
        color: Notifs.unread > 0 ? Theme.text : Theme.textDim; filled: Notifs.unread > 0 }
    Rectangle {   // unread count
        visible: Notifs.unread > 0
        x: parent.width / 2 + 4; y: parent.height / 2 - 18
        height: 16; width: Math.max(16, cnt.implicitWidth + 8); radius: 8; color: Theme.accent
        Text { id: cnt; anchors.centerIn: parent; text: Notifs.unread > 9 ? "9+" : Notifs.unread; color: "#101218"
            font.family: Theme.font; font.pixelSize: 10; font.weight: Font.Bold }
    }

    property string tab: "pc"
    readonly property var list: tab === "phone" ? Notifs.phoneItems : Notifs.pcItems
    readonly property int shown: Math.min(list.length, 6)
    Popover {
        id: pop
        target: w
        fancy: true
        panelWidth: 390
        panelHeight: 104 + (list.length === 0 ? 96 : shown * 80 + 8) + (list.length > 6 ? 24 : 0)
        onOpenChanged: if (open) Notifs.markReadSrc(w.tab)

        Item {
            anchors.fill: parent
            // ---- header ----
            Text { x: 18; y: 18; text: "Notifications"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
            Row { anchors.right: parent.right; anchors.rightMargin: 14; y: 12; spacing: 6
                Rectangle {   // do not disturb
                    height: 30; width: dndRow.implicitWidth + 22; radius: 15
                    color: Quick.dndOn ? Theme.accent : (dm.containsMouse ? Theme.tileFillHover : Qt.rgba(1, 1, 1, 0.08))
                    Row { id: dndRow; anchors.centerIn: parent; spacing: 5
                        Icon { name: "bedtime"; size: 16; anchors.verticalCenter: parent.verticalCenter; color: Quick.dndOn ? "#101218" : Theme.text }
                        Text { text: Quick.dndOn ? "Do Not Disturb on" : "Do Not Disturb"; anchors.verticalCenter: parent.verticalCenter
                            color: Quick.dndOn ? "#101218" : Theme.text; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium } }
                    MouseArea { id: dm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Quick.toggle("dnd") }
                }
                Rectangle {   // clear all
                    visible: w.list.length > 0
                    height: 30; width: clrTxt.implicitWidth + 22; radius: 15
                    color: cm.containsMouse ? Theme.tileFillHover : Qt.rgba(1, 1, 1, 0.08)
                    Text { id: clrTxt; anchors.centerIn: parent; text: "Clear"; color: Theme.text; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium }
                    MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { Notifs.clearSrc(w.tab); if (w.tab === "pc") Quickshell.execDetached(["dms", "ipc", "call", "notifications", "clearAll"]); } }
                }
            }
            // ---- tabs: This PC | Phone ----
            Row { x: 14; y: 54; spacing: 6
                Repeater { model: [ { k: "pc", l: "This PC", ic: "computer", n: Notifs.unread - Notifs.unreadPhone, t: Notifs.pcItems.length },
                                    { k: "phone", l: "Phone", ic: "smartphone", n: Notifs.unreadPhone, t: Notifs.phoneItems.length } ]
                    delegate: Rectangle {
                        id: tb
                        required property var modelData
                        readonly property bool on: w.tab === modelData.k
                        height: 28; width: tl.implicitWidth + 36; radius: 14
                        color: on ? Theme.accent : (tm.containsMouse ? Theme.tileFillHover : Qt.rgba(1, 1, 1, 0.08))
                        Row { id: tl; anchors.centerIn: parent; spacing: 5
                            Icon { name: tb.modelData.ic; size: 15; anchors.verticalCenter: parent.verticalCenter; color: tb.on ? "#101218" : Theme.text }
                            Text { text: tb.modelData.l + (tb.modelData.t > 0 ? "  " + tb.modelData.t : ""); anchors.verticalCenter: parent.verticalCenter
                                color: tb.on ? "#101218" : Theme.text; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium } }
                        Rectangle { visible: !tb.on && tb.modelData.n > 0; x: parent.width - 9; y: -2; width: 10; height: 10; radius: 5; color: Theme.accent }
                        MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { w.tab = tb.modelData.k; Notifs.markReadSrc(tb.modelData.k); } }
                    } } }
            // ---- empty state ----
            Column { visible: w.list.length === 0; anchors.horizontalCenter: parent.horizontalCenter; y: 112; spacing: 8
                Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "notifications_off"; size: 30; color: Theme.textDim }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: w.tab === "phone" ? "No phone notifications" : "No new notifications"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: w.tab === "phone" ? "From KDE Connect · repeats are collapsed" : "Shows what arrived since the dock started"; color: Theme.textDim; opacity: 0.7; font.family: Theme.font; font.pixelSize: 10 } }
            // ---- list ----
            Column { x: 12; y: 96; width: parent.width - 24; spacing: 6
                Repeater { model: w.list.slice(0, 6)
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        function ago(ms) { const s = Math.max(0, Math.floor((Date.now() - ms) / 1000)); return s < 60 ? "now" : (s < 3600 ? Math.floor(s / 60) + "m" : (s < 86400 ? Math.floor(s / 3600) + "h" : Math.floor(s / 86400) + "d")); }
                        readonly property string iconSrc: modelData.icon.length === 0 ? "" : (modelData.icon[0] === "/" ? "file://" + modelData.icon : Quickshell.iconPath(modelData.icon, true))
                        width: parent.width; height: 74; radius: 14
                        color: rm.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : Theme.tileFill
                        border.width: 1; border.color: modelData.urgency >= 2 ? Theme.bad : Theme.hairline
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Rectangle { x: 10; y: 12; width: 40; height: 40; radius: 12; color: Qt.rgba(1, 1, 1, 0.08); clip: true
                            Image { anchors.fill: parent; anchors.margins: 4; fillMode: Image.PreserveAspectFit; asynchronous: true; source: row.iconSrc; visible: status === Image.Ready }
                            Icon { anchors.centerIn: parent; name: "notifications"; size: 20; color: Theme.textDim; visible: row.iconSrc === "" }
                        }
                        Column { x: 60; y: 9; width: parent.width - 60 - 14; spacing: 1
                            Row { width: parent.width
                                Text { width: parent.width - agoT.implicitWidth - 6; elide: Text.ElideRight; textFormat: Text.PlainText; text: row.modelData.app || "Notification"
                                    color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.Medium }
                                Text { id: agoT; text: row.ago(row.modelData.time); color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10 } }
                            Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText; text: row.modelData.summary
                                color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Text { width: parent.width; height: 32; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; textFormat: Text.PlainText; text: row.modelData.body
                                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11; visible: text !== "" }
                        }
                        MouseArea { id: rm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Notifs.dismiss(row.modelData.id) }
                        Icon { visible: rm.containsMouse; x: parent.width - 24; y: 6; name: "close"; size: 14; color: Theme.textDim }
                    }
                }
                Text { visible: w.list.length > 6; width: parent.width; horizontalAlignment: Text.AlignHCenter; height: 18
                    text: "+" + (w.list.length - 6) + " more · tap one to dismiss"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10 }
            }
        }
    }
}
