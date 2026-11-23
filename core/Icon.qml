import QtQuick

// Material Symbols glyph by ligature name, e.g. <Icon name="notifications"/>.
// Font is loaded from the system (installed by DankMaterialShell or the
// google material-symbols package) so we don't vendor 14 MB into the repo.
Text {
    property string name: ""
    property int size: 20
    property bool filled: false           // Material Symbols FILL axis: solid glyph (used for active states)
    text: name
    color: Theme.text
    font.family: face.status === FontLoader.Ready ? face.name : "Material Symbols Rounded"
    font.pixelSize: size
    renderType: Text.QtRendering          // sharp when the dropdown is scaled
    font.variableAxes: ({ "FILL": filled ? 1 : 0 })
    FontLoader {
        id: face
        source: "file:///usr/share/quickshell/dms/assets/fonts/material-design-icons/variablefont/MaterialSymbolsRounded%5BFILL,GRAD,opsz,wght%5D.ttf"
    }
}
