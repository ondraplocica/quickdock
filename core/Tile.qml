import QtQuick

// Base card every widget builds on: dark fill, hairline border, hover lift.
Rectangle {
    id: tile
    property alias hovered: hh.hovered
    property string instanceId: ""       // full widget id from dock.json, e.g. "folder:work" (several instances of one widget)
    property var config: ({})            // per-widget block from dock.json "widgetConfig"
    property bool interactive: true
    property bool active: false          // e.g. playing / running -> accent tint
    signal clicked()

    implicitHeight: Theme.tileHeight
    radius: Theme.tileRadius
    color: active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20)
                  : (interactive && hovered ? Theme.tileFillHover : Theme.tileBg)
    border.width: 1
    border.color: active ? Theme.accent : (interactive && hovered ? Theme.hairlineHover : Theme.hairline)
    scale: interactive && hovered ? 1.025 : 1

    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Behavior on border.color { ColorAnimation { duration: Theme.fast } }
    Behavior on scale { NumberAnimation { duration: Theme.medium; easing.type: Easing.OutBack } }
    Behavior on implicitWidth { NumberAnimation { duration: Theme.medium; easing.type: Easing.OutCubic } }

    HoverHandler { id: hh }
    TapHandler { onTapped: tile.clicked() }
}
