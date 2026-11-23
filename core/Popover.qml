import QtQuick
import Quickshell
import Quickshell.Hyprland

// Glass panel that opens next to a Tile (above a bottom dock, below a top dock) and follows Dock.dropScale.
// Declare as a child of the widget:
//   Popover { id: pop; target: w; panelWidth: 320; panelHeight: 200; ...content... }
// Toggle with `pop.open = !pop.open`. Click-outside closes it (Hyprland focus grab).
PopupWindow {
    id: pop
    property Item target
    property bool open: false
    property int panelWidth: 320
    property int panelHeight: 220
    property bool fancy: false            // glass look: vertical gradient + top highlight + a touch of translucency
    property real glassAlpha: 0.84        // panel opacity in fancy mode (the compositor blurs what is behind)
    property bool bare: false             // no background of its own: the content draws the panel (quick settings styles)
    default property alias content: inner.data

    // Anchor to an invisible item that reaches past the dock edge, so the panel starts a clear gap
    // beyond the dock instead of overlapping it (anchor.margins only constrain screen-edge sliding).
    anchor.item: ghost
    // Preferred side comes from Dock.dropdownSide; if it doesn't fit (e.g. "below" on a bottom dock) it flips.
    anchor.edges: Dock.popBelow ? Edges.Bottom : Edges.Top
    anchor.gravity: Dock.popBelow ? Edges.Bottom : Edges.Top
    anchor.adjustment: PopupAdjustment.Slide | PopupAdjustment.Flip

    implicitWidth: Math.round(panelWidth * Dock.dropScale)
    implicitHeight: Math.round(panelHeight * Dock.dropScale)
    color: "transparent"
    visible: open || hideTimer.running
    onOpenChanged: if (!open) hideTimer.restart()

    Item {
        id: ghost
        parent: pop.target
        readonly property real extra: Dock.popGap / Dock.uiScale
        x: 0
        y: Dock.popBelow ? 0 : -extra
        width: pop.target ? pop.target.width : 0
        height: (pop.target ? pop.target.height : 0) + extra
    }
    Connections { target: Dock; function onCloseAll() { pop.open = false; } }
    Timer { id: hideTimer; interval: Theme.medium + 40 }
    HyprlandFocusGrab { windows: [pop]; active: pop.open; onCleared: pop.open = false }

    Rectangle {
        id: body
        anchors.fill: parent
        radius: Theme.dockRadius * Dock.dropScale
        // every dropdown shares the quick-settings surface: tinted Material panel, opacity = Dock "Panel opacity"
        // (the compositor blurs what shows through). `fancy`/`glassAlpha` are kept only so old callers still load.
        color: pop.bare ? "transparent" : QsStyle.panel
        border.width: pop.bare ? 0 : 1
        border.color: QsStyle.panelEdge
        clip: true
        opacity: pop.open ? 1 : 0
        scale: pop.open ? 1 : 0.94
        transformOrigin: Dock.popBelow ? Item.Top : Item.Bottom
        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        Behavior on scale { NumberAnimation { duration: Theme.medium; easing.type: Easing.OutBack } }

        // Content is laid out at 1x and scaled as a whole, so every widget gets sizing for free.
        Item {
            id: inner
            width: pop.panelWidth
            height: pop.panelHeight
            scale: Dock.dropScale
            transformOrigin: Item.TopLeft
        }
    }
}
