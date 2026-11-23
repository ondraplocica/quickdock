import QtQuick

// Label  [-] value [+]
Row {
    id: st
    property string label: ""
    property string valueText: ""
    signal minus()
    signal plus()
    spacing: 12
    Text { anchors.verticalCenter: parent.verticalCenter; text: st.label; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; width: 140 }
    IconButton { width: 30; height: 30; radius: 15; icon: "remove"; onClicked: st.minus() }
    Text { anchors.verticalCenter: parent.verticalCenter; text: st.valueText; color: Theme.text; font.family: Theme.font; font.pixelSize: 13
        width: 52; horizontalAlignment: Text.AlignHCenter }
    IconButton { width: 30; height: 30; radius: 15; icon: "add"; onClicked: st.plus() }
}
