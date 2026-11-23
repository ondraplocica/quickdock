pragma Singleton
import QtQuick

// Design tokens for the whole dock. Widgets never hard-code colours or radii.
QtObject {
    readonly property color text: "#f2f2f5"
    readonly property color textDim: Qt.rgba(1, 1, 1, 0.55)
    property color accent: "#8ab4ff"
    readonly property color good: "#66d98b"
    readonly property color warn: "#ffb74d"
    readonly property color bad: "#ef5350"

    readonly property color dockFill: Qt.rgba(0.05, 0.05, 0.07, Dock.barOpacity)
    // base fill of a Tile: in "pills" style every tile is its own floating pill, so it needs the bar fill
    readonly property color tileBg: Dock.style === "pills" ? dockFill : Qt.rgba(0, 0, 0, 0.30)
    readonly property color popFill: Qt.rgba(0.07, 0.07, 0.09, Dock.popOpacity)
    readonly property color tileFill: Qt.rgba(0, 0, 0, 0.30)
    readonly property color tileFillHover: Qt.rgba(1, 1, 1, 0.10)
    readonly property color hairline: Qt.rgba(1, 1, 1, 0.08)
    readonly property color hairlineHover: Qt.rgba(1, 1, 1, 0.18)

    readonly property int dockRadius: Dock.square ? 6 : 22
    readonly property int tileRadius: Dock.square ? 6 : 16
    readonly property int tileHeight: 52
    readonly property int gap: 8

    readonly property int fast: 160
    readonly property int medium: 280
    readonly property string font: "Inter"

    function load(v) { return v > 80 ? bad : (v > 55 ? warn : good); }
}
