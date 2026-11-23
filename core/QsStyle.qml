pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Look of the quick-settings panel: Material You, with an optional "blur behind".
// Colours are the Material 3 palette DMS generates from your theme / wallpaper
// (~/.cache/DankMaterialShell/dms-colors.json, read live); an accent-free tonal fallback is used if that file is missing.
// `panelOpacity` (dock.json, 0.30..1.0, Dock settings -> Panel opacity) makes the surfaces translucent; Hyprland blurs
// what is behind them (layerrule blur_popups, which needs alpha above ignore_alpha 0.1, so the floor is 30%).
Singleton {
    id: s

    // ---- DMS Material 3 palette (dark scheme), live ----
    property var m3: ({})
    FileView {
        id: pal
        path: Quickshell.env("HOME") + "/.cache/DankMaterialShell/dms-colors.json"
        printErrors: false              // only exists with DankMaterialShell; the built-in palette is used otherwise
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { const j = JSON.parse(text()); s.m3 = (j.colors && j.colors.dark) || ({}); } catch (e) { s.m3 = ({}); } }
    }
    function c(name, fallback) { const v = m3[name]; return (typeof v === "string" && v.length) ? v : fallback; }

    readonly property real alpha: (typeof Dock.cfg.panelOpacity === "number") ? Math.max(0.30, Math.min(1.0, Dock.cfg.panelOpacity)) : 0.80
    function withAlpha(col, a) { return Qt.rgba(col.r, col.g, col.b, Math.max(0, Math.min(1, a))); }

    function mix(a0, b0, t) { const a = Qt.color(a0), b = Qt.color(b0); return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1); }
    readonly property color _prim: Qt.color(c("primary", "#cba6f7"))

    // base colours (opaque). Pastel: the dark surfaces carry a soft wash of the primary, and "on" is a light pastel fill.
    readonly property color _panel: mix(c("surface_container", "#211f26"), _prim, 0.10)
    readonly property color _card: mix(c("surface_container_high", "#2b2930"), _prim, 0.17)
    readonly property color _cardOn: mix(_prim, "#ffffff", 0.06)
    readonly property color _icon: mix(c("surface_container_highest", "#36343b"), _prim, 0.24)
    readonly property color _edge: c("outline_variant", "#49454f")

    // surfaces (carry the panel opacity; cards sit a little denser than the panel so they stay distinct)
    readonly property color panel: withAlpha(_panel, alpha)
    readonly property color panelEdge: withAlpha(_edge, 0.55)
    readonly property color card: withAlpha(_card, alpha + 0.10)
    readonly property color cardOn: withAlpha(_cardOn, alpha + 0.15)
    readonly property color iconBg: withAlpha(_icon, alpha + 0.20)
    readonly property color trackFill: withAlpha(_icon, alpha + 0.20)

    // ink
    readonly property color accent: c("primary", Theme.accent)
    readonly property color onAccent: c("on_primary", "#1e1e2e")
    readonly property color sliderFill: c("secondary", "#b4befe")   // periwinkle next to the lavender tiles
    readonly property color dotOn: mix(c("on_primary", "#1e1e2e"), _prim, 0.12)   // dark disc on a pastel tile
    readonly property color onDot: _prim
    readonly property color text: c("on_surface", "#e6e1e9")
    readonly property color textDim: c("on_surface_variant", "#cac4d0")
    readonly property color onCardOn: c("on_primary", "#1e1e2e")
    function ink(on) { return on ? onCardOn : text; }
    function inkDim(on) { return on ? withAlpha(onCardOn, 0.68) : textDim; }

    readonly property int panelRadius: 28
    readonly property int cardRadius: 24
}
