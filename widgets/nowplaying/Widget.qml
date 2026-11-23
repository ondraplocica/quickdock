import QtQuick
import Quickshell.Services.Mpris
import "../../core"

Tile {
    id: w
    readonly property var players: Mpris.players.values
    readonly property var p: players.find(x => x.isPlaying) ?? players[0] ?? null
    readonly property bool has: p !== null
    readonly property bool playing: has && p.isPlaying
    active: playing
    implicitWidth: row.implicitWidth + 24
    clip: true
    onClicked: if (has) p.togglePlaying()

    property real pos: 0
    Timer { interval: 1000; repeat: true; running: w.playing; triggeredOnStart: true
        onTriggered: w.pos = w.has ? w.p.position : 0 }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        x: 12; spacing: 10
        Rectangle {
            width: Theme.tileHeight - 16; height: width; radius: 10; clip: true
            anchors.verticalCenter: parent.verticalCenter; color: Theme.tileFill
            Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true
                source: w.has ? (w.p.trackArtUrl ?? "") : ""
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 400 } } }
        }
        Row {   // equalizer
            visible: w.playing; spacing: 2; height: 16; anchors.verticalCenter: parent.verticalCenter
            Repeater { model: 4
                delegate: Rectangle {
                    required property int index
                    width: 3; radius: 1.5; color: Theme.accent; anchors.bottom: parent.bottom; height: 4
                    SequentialAnimation on height { loops: Animation.Infinite; running: w.playing
                        NumberAnimation { to: 16; duration: 280 + index * 90; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 3; duration: 320 + index * 70; easing.type: Easing.InOutSine } } }
            }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Text { textFormat: Text.PlainText; width: Math.min(implicitWidth, 190); elide: Text.ElideRight
                text: w.has ? (w.p.trackTitle || "Unknown") : "Nothing playing"
                color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
            Text { textFormat: Text.PlainText; visible: w.has && !!w.p.trackArtist; width: Math.min(implicitWidth, 190); elide: Text.ElideRight
                text: w.has ? w.p.trackArtist : ""
                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 }
        }
    }
    Rectangle {   // progress line
        anchors { left: parent.left; bottom: parent.bottom }
        height: 2; color: Theme.accent
        width: w.has && w.p.length > 0 ? parent.width * Math.min(1, w.pos / w.p.length) : 0
        Behavior on width { NumberAnimation { duration: 900 } }
    }
}
