import QtQuick
import "../../core"

// Dropdown content for the peripherals widget: one row per device (ring + name + state + %). Pure view; all text PlainText.
Item {
    id: list
    property var devices: []                 // [{id,name,kind,pct,state,source}] already filtered/renamed
    property bool loading: false
    property bool editing: false
    property var allDevices: []              // [{key,name,shownName,kind,pct,state,hiddenNow}] everything detected (edit mode)
    property bool showWired: true
    signal editToggled()
    signal visibilityChanged(string key, bool visible)
    signal renameRequested(string key, string text)
    signal wiredToggled(bool v)
    readonly property int rowsN: editing ? allDevices.length : Math.max(devices.length, 1)
    implicitWidth: 320
    implicitHeight: 32 + 34 + rowsN * (editing ? 48 : 52) + Math.max(rowsN - 1, 0) * 4 + (editing ? 48 : hiddenH)
    readonly property var hiddenList: allDevices.filter(d => d.hiddenNow || (!showWired && d.state === "wired"))
    readonly property int hiddenCount: hiddenList.length
    readonly property int hiddenH: hiddenCount > 0 ? 30 + hiddenCount * 44 + (hiddenCount - 1) * 4 : 0

    function iconFor(k) {
        switch (k) {
        case "mouse": return "mouse";
        case "keyboard": return "keyboard";
        case "headset": case "headphones": case "audio-headset": case "audio-headphones": return "headphones";
        case "gaming-input": return "sports_esports";
        case "phone": return "smartphone";
        case "tablet": return "tablet";
        case "touchpad": return "touch_app";
        }
        return "devices_other";
    }
    function ago(ts) {
        const s = Math.max(0, Math.floor(Date.now() / 1000) - (ts || 0));
        if (s < 90) return "just now";
        if (s < 5400) return Math.round(s / 60) + " min ago";
        if (s < 129600) return Math.round(s / 3600) + " h ago";
        return Math.round(s / 86400) + " d ago";
    }
    function colorFor(d) { return d.pct === null || d.pct === undefined ? Theme.textDim : (d.pct <= 15 && d.state !== "charging" ? Theme.bad : (d.pct <= 30 && d.state !== "charging" ? Theme.warn : Theme.good)); }
    function stateText(d) {
        if (d.state === "asleep") return "Last reading " + ago(d.ts);
        if (d.state === "wired") return "Wired (USB)";
        const m = { charging: "Charging", discharging: "On battery", full: "Fully charged" };
        return m[d.state] || "";
    }

    Column {
        anchors { fill: parent; margins: 16 } spacing: 4
        Item { width: parent.width; height: 34
            Text { anchors.verticalCenter: parent.verticalCenter; text: list.editing ? "Edit peripherals" : "Peripherals"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
            IconButton { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 32; height: 32; radius: 16
                icon: list.editing ? "check" : "edit"; active: list.editing; onClicked: list.editToggled() } }
        // ---------------- edit mode: every detected device, eye = show on the bar, name = rename ----------------
        Repeater { model: list.editing ? list.allDevices : []
            delegate: Item { id: er; required property var modelData; width: parent.width; height: 48
                readonly property bool off: modelData.hiddenNow || (!list.showWired && modelData.state === "wired")
                opacity: off ? 0.5 : 1
                Rectangle { anchors.fill: parent; radius: 12; color: Theme.tileFill; border.width: 1; border.color: Theme.hairline }
                IconButton { x: 6; anchors.verticalCenter: parent.verticalCenter; width: 34; height: 34; radius: 17
                    icon: modelData.hiddenNow ? "visibility_off" : "visibility"
                    onClicked: list.visibilityChanged(modelData.key, modelData.hiddenNow) }
                Icon { x: 46; anchors.verticalCenter: parent.verticalCenter; name: list.iconFor(modelData.kind); size: 18; color: Theme.textDim }
                Column { anchors.verticalCenter: parent.verticalCenter; x: 74; width: parent.width - 74 - 12
                    TextInput { id: ti; width: parent.width; clip: true; selectByMouse: true; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                        text: modelData.shownName
                        onEditingFinished: list.renameRequested(modelData.key, text) }
                    Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10
                        text: modelData.state === "absent" ? "Not detected right now" : (list.stateText(modelData) || (modelData.pct !== null && modelData.pct !== undefined ? modelData.pct + "%" : "No battery reading")) } }
            } }
        Item { visible: list.editing; width: parent.width; height: 48
            Rectangle { anchors.fill: parent; radius: 12; color: Theme.tileFill; border.width: 1; border.color: Theme.hairline }
            Text { x: 14; anchors.verticalCenter: parent.verticalCenter; text: "Show wired devices (no battery)"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
            Rectangle { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; width: 40; height: 22; radius: 11
                color: list.showWired ? Theme.accent : Qt.rgba(1, 1, 1, 0.14)
                Rectangle { y: 3; x: list.showWired ? 21 : 3; width: 16; height: 16; radius: 8; color: "#fff"; Behavior on x { NumberAnimation { duration: 130 } } }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: list.wiredToggled(!list.showWired) } } }
        // ---------------- normal mode ----------------
        Text { visible: !list.editing && list.devices.length === 0; width: parent.width; wrapMode: Text.WordWrap; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12; height: 52
            text: list.loading ? "Checking…" : "No devices with a battery reading. Logitech via Solaar, Bluetooth and upower devices appear here." }
        Repeater { model: list.editing ? [] : list.devices
            delegate: Item { required property var modelData; width: parent.width; height: 52
                Rectangle { anchors.fill: parent; radius: 12; color: Theme.tileFill; border.width: 1; border.color: Theme.hairline }
                Item { id: rg; x: 10; width: 36; height: 36; anchors.verticalCenter: parent.verticalCenter
                    Ring { anchors.centerIn: parent; size: 36; thickness: 3.5; value: modelData.pct === null || modelData.pct === undefined ? 0 : modelData.pct / 100; fill: list.colorFor(modelData); endDot: modelData.pct !== null && modelData.pct !== undefined }
                    Icon { anchors.centerIn: parent; name: list.iconFor(modelData.kind); size: 17; color: modelData.pct === null || modelData.pct === undefined ? Theme.textDim : Theme.text } }
                Column { anchors.verticalCenter: parent.verticalCenter; x: 58; width: parent.width - 58 - 62
                    Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText; text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                    Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText; text: list.stateText(modelData); color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11; visible: text !== "" } }
                Row { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                    Icon { visible: modelData.state === "charging"; name: "bolt"; size: 14; color: Theme.good; anchors.verticalCenter: parent.verticalCenter }
                    Text { visible: modelData.pct !== null && modelData.pct !== undefined; anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: modelData.pct + "%"; color: list.colorFor(modelData); font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold } } } }
        // ---- hidden devices: still visible here with their reading; the eye brings one back onto the bar ----
        Column { visible: !list.editing && list.hiddenCount > 0; width: parent.width; spacing: 4
            Text { text: "HIDDEN FROM THE BAR"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10; font.letterSpacing: 1.2; height: 26; verticalAlignment: Text.AlignBottom }
            Repeater { model: list.hiddenList
                delegate: Item { required property var modelData; width: parent.width; height: 44; opacity: 0.7
                    Rectangle { anchors.fill: parent; radius: 12; color: Theme.tileFill; border.width: 1; border.color: Theme.hairline }
                    IconButton { x: 6; anchors.verticalCenter: parent.verticalCenter; width: 32; height: 32; radius: 16; icon: "visibility_off"
                        onClicked: { if (modelData.hiddenNow) list.visibilityChanged(modelData.key, true); else list.wiredToggled(true); } }
                    Icon { x: 46; anchors.verticalCenter: parent.verticalCenter; name: list.iconFor(modelData.kind); size: 18; color: Theme.textDim }
                    Column { anchors.verticalCenter: parent.verticalCenter; x: 74; width: parent.width - 74 - 62
                        Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText; text: modelData.shownName; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                        Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10
                            text: modelData.state === "absent" ? "Not detected right now" : (modelData.hiddenNow ? "Tap the eye to show on the bar" : "Hidden: wired devices are off") } }
                    Text { visible: modelData.pct !== null && modelData.pct !== undefined; anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                        text: modelData.pct + "%"; color: list.colorFor(modelData); font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Bold }
                }
            }
        }
    }
}
