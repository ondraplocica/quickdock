import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"

// Quick convert: currency (ECB reference rates via fx.py, cached 1 h) and common units.
// Config (dock.json -> widgetConfig.quickconvert):
//   { "pairs": [["EUR","CZK"],["USD","CZK"]], "from": "EUR", "to": "CZK" }
// Pinned pairs show as chips; the star pins/unpins the current pair. The bar tile is just an icon.
Tile {
    id: w
    implicitWidth: ic.implicitWidth + 24
    readonly property var qc: (Dock.cfg.widgetConfig || {})[instanceId || "quickconvert"] || config || ({})
    readonly property var pairs: Array.isArray(qc.pairs) ? qc.pairs : [["EUR", "CZK"], ["USD", "CZK"], ["CZK", "EUR"]]
    readonly property string script: String(Qt.resolvedUrl("fx.py")).replace("file://", "")

    // ---------- state ----------
    property string mode: "money"                 // money | units
    property string amount: "1"
    property string from: qc.from || (pairs[0] ? pairs[0][0] : "EUR")
    property string to: qc.to || (pairs[0] ? pairs[0][1] : "CZK")
    property var rates: ({})
    property string rateState: "loading"          // loading | ok | offline
    property string rateDate: ""
    property bool stale: false
    property string picker: ""                    // "" | "from" | "to"
    property int cat: 0
    property int uFrom: 0
    property int uTo: 1

    // ---------- units ----------
    readonly property var cats: [
        { n: "Length", u: [["m", 1], ["km", 1000], ["cm", 0.01], ["mm", 0.001], ["in", 0.0254], ["ft", 0.3048], ["yd", 0.9144], ["mi", 1609.344]] },
        { n: "Mass", u: [["kg", 1], ["g", 0.001], ["lb", 0.45359237], ["oz", 0.028349523125]] },
        { n: "Volume", u: [["l", 1], ["ml", 0.001], ["gal", 3.785411784], ["fl oz", 0.0295735295625], ["cup", 0.2365882365]] },
        { n: "Temp", u: [["°C", 0], ["°F", 0], ["K", 0]] }
    ]
    readonly property var curUnits: cats[cat].u
    function setCat(i) { uFrom = 0; uTo = 1; cat = i; }
    function tempToC(v, u) { return u === 1 ? (v - 32) * 5 / 9 : (u === 2 ? v - 273.15 : v); }
    function tempFromC(c, u) { return u === 1 ? c * 9 / 5 + 32 : (u === 2 ? c + 273.15 : c); }

    // ---------- conversion ----------
    readonly property real amt: { const v = parseFloat(String(amount).replace(",", ".")); return isNaN(v) ? 0 : v; }
    readonly property bool haveRates: rateState === "ok" && rates[from] > 0 && rates[to] > 0
    readonly property real result: {
        if (mode === "money") return haveRates ? amt * rates[to] / rates[from] : NaN;
        if (cat === 3) return tempFromC(tempToC(amt, uFrom), uTo);
        return amt * curUnits[uFrom][1] / curUnits[uTo][1];
    }
    readonly property real unitRate: haveRates ? rates[to] / rates[from] : NaN
    function fmt(x) {
        if (!isFinite(x)) return "–";
        const a = Math.abs(x), d = a >= 100 ? 2 : (a >= 1 ? 3 : 5);
        return x.toLocaleString(Qt.locale("en_US"), "f", d).replace(/(\.\d*?)0+$/, "$1").replace(/\.$/, "");
    }
    readonly property bool pinned: pairs.some(p => p[0] === from && p[1] === to)
    function togglePin() {
        const next = pinned ? pairs.filter(p => !(p[0] === from && p[1] === to)) : pairs.concat([[from, to]]).slice(-8);
        Dock.saveWidget(instanceId || "quickconvert", { pairs: next });
    }
    function swap() {
        if (mode === "money") { const t = from; from = to; to = t; }
        else { const t = uFrom; uFrom = uTo; uTo = t; }
    }
    readonly property var codes: {
        const pri = ["CZK", "EUR", "USD", "GBP", "PLN", "CHF", "HUF", "JPY"];
        const all = Object.keys(rates).sort();
        return pri.filter(c => all.indexOf(c) >= 0).concat(all.filter(c => pri.indexOf(c) < 0));
    }

    // ---------- rates ----------
    function toggle() { if (!pop.open) refresh(); pop.open = !pop.open; }
    function refresh() { if (!fx.running) fx.running = true; }
    Timer { interval: 1800000; running: true; repeat: true; triggeredOnStart: true; onTriggered: w.refresh() }
    Process {
        id: fx
        command: ["python3", "-I", w.script, "rates"]
        stdout: StdioCollector { onStreamFinished: {
            try {
                const r = JSON.parse(text);
                if (r.ok) { w.rates = r.rates; w.rateDate = r.date; w.stale = !!r.stale; w.rateState = "ok"; }
                else w.rateState = "offline";
            } catch (e) { w.rateState = "offline"; } } }
    }
    onClicked: toggle()

    Icon { id: ic; anchors.centerIn: parent; name: "currency_exchange"; size: 22; color: pop.open ? Theme.accent : Theme.text }

    Popover {
        id: pop
        target: w
        panelWidth: 320
        panelHeight: 330
        onOpenChanged: if (!open) w.picker = ""
        Item {
            id: p
            anchors.fill: parent
            readonly property color chipFill: Qt.rgba(1, 1, 1, 0.07)

            // header: title + mode switch
            Row { id: head; x: 16; y: 14; spacing: 8
                Text { text: "Convert"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                Item { width: 6; height: 1 }
                Repeater { model: [ { id: "money", l: "Currency" }, { id: "units", l: "Units" } ]
                    delegate: Rectangle { required property var modelData
                        width: lbl.implicitWidth + 20; height: 26; radius: 13
                        color: w.mode === modelData.id ? Theme.accent : p.chipFill
                        Text { id: lbl; anchors.centerIn: parent; text: modelData.l; textFormat: Text.PlainText
                            color: w.mode === modelData.id ? "#101218" : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { w.mode = modelData.id; w.picker = ""; } } } }
            }

            // pinned pairs (currency) or categories (units)
            Flow { id: chips; x: 16; y: 50; width: parent.width - 32; spacing: 6
                Repeater { model: w.mode === "money" ? w.pairs : w.cats
                    delegate: Rectangle { required property var modelData; required property int index
                        readonly property bool sel: w.mode === "money" ? (modelData[0] === w.from && modelData[1] === w.to) : w.cat === index
                        width: cl.implicitWidth + 18; height: 26; radius: 13
                        color: sel ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28) : p.chipFill
                        border.width: sel ? 1 : 0; border.color: Theme.accent
                        Text { id: cl; anchors.centerIn: parent; textFormat: Text.PlainText
                            text: w.mode === "money" ? modelData[0] + " → " + modelData[1] : modelData.n
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: { if (w.mode === "money") { w.from = modelData[0]; w.to = modelData[1]; } else w.setCat(index); w.picker = ""; } } } }
            }

            // amount
            Rectangle { id: amtBox; x: 16; y: 50 + chips.height + 12; width: parent.width - 32; height: 52; radius: 14
                color: Qt.rgba(0, 0, 0, 0.30); border.width: 1; border.color: af.activeFocus ? Theme.accent : Theme.hairline
                TextInput { id: af; anchors { left: parent.left; leftMargin: 14; right: fromBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    text: w.amount; onTextChanged: w.amount = text; selectByMouse: true; clip: true
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 22; font.weight: Font.DemiBold
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    Keys.onEscapePressed: pop.open = false }
                Rectangle { id: fromBtn; anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    width: fl.implicitWidth + 28; height: 34; radius: 17; color: w.picker === "from" ? Theme.accent : p.chipFill
                    Row { anchors.centerIn: parent; spacing: 2
                        Text { id: fl; anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText
                            text: w.mode === "money" ? w.from : w.curUnits[w.uFrom][0]
                            color: w.picker === "from" ? "#101218" : Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Icon { anchors.verticalCenter: parent.verticalCenter; name: "expand_more"; size: 16; color: w.picker === "from" ? "#101218" : Theme.textDim } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: w.picker = w.picker === "from" ? "" : "from" } }
            }

            // swap + pin
            Item { id: mid; x: 16; y: amtBox.y + amtBox.height + 2; width: parent.width - 32; height: 34
                Rectangle { anchors.centerIn: parent; width: 34; height: 34; radius: 17; color: p.chipFill
                    scale: sm.pressed ? 0.9 : 1; Behavior on scale { NumberAnimation { duration: 90 } }
                    Icon { anchors.centerIn: parent; name: "swap_vert"; size: 20 }
                    MouseArea { id: sm; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: w.swap() } }
                Rectangle { visible: w.mode === "money"; anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 30; height: 30; radius: 15; color: "transparent"
                    Icon { anchors.centerIn: parent; name: "star"; size: 20; filled: w.pinned; color: w.pinned ? Theme.warn : Theme.textDim }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: w.togglePin() } }
            }

            // result
            Rectangle { id: resBox; x: 16; y: mid.y + mid.height + 2; width: parent.width - 32; height: 64; radius: 14
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14); border.width: 1; border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
                Text { anchors { left: parent.left; leftMargin: 14; right: toBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    text: w.mode === "money" && !w.haveRates ? (w.rateState === "loading" ? "Loading rates…" : "Rates unavailable") : w.fmt(w.result)
                    elide: Text.ElideRight; textFormat: Text.PlainText
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 26; font.weight: Font.Bold }
                Rectangle { id: toBtn; anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    width: tl.implicitWidth + 28; height: 34; radius: 17; color: w.picker === "to" ? Theme.accent : p.chipFill
                    Row { anchors.centerIn: parent; spacing: 2
                        Text { id: tl; anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText
                            text: w.mode === "money" ? w.to : w.curUnits[w.uTo][0]
                            color: w.picker === "to" ? "#101218" : Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Icon { anchors.verticalCenter: parent.verticalCenter; name: "expand_more"; size: 16; color: w.picker === "to" ? "#101218" : Theme.textDim } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: w.picker = w.picker === "to" ? "" : "to" } }
            }

            // footer: rate + freshness
            Text { x: 18; y: resBox.y + resBox.height + 10; width: parent.width - 36; textFormat: Text.PlainText; elide: Text.ElideRight
                color: w.stale || w.rateState === "offline" ? Theme.warn : Theme.textDim; font.family: Theme.font; font.pixelSize: 12
                text: w.mode === "money"
                    ? (w.haveRates ? "1 " + w.from + " = " + w.fmt(w.unitRate) + " " + w.to + " · ECB " + w.rateDate + (w.stale ? " · offline, cached" : "")
                                   : (w.rateState === "offline" ? "No cached rates yet and the rate service is unreachable" : ""))
                    : (w.cat === 3 ? "Temperature" : "1 " + w.curUnits[w.uFrom][0] + " = " + w.fmt(w.curUnits[w.uFrom][1] / w.curUnits[w.uTo][1]) + " " + w.curUnits[w.uTo][0]) }

            // picker overlay (covers everything below the amount row)
            Rectangle { id: pick; visible: w.picker !== ""; x: 8; y: mid.y; width: parent.width - 16; height: parent.height - mid.y - 8
                radius: 14; color: Theme.popFill; border.width: 1; border.color: Theme.hairlineHover; clip: true
                Flickable { anchors.fill: parent; anchors.margins: 8; contentHeight: grid.height; clip: true
                    Flow { id: grid; width: parent.width; spacing: 6
                        Repeater { model: w.mode === "money" ? w.codes : w.curUnits.map(u => u[0])
                            delegate: Rectangle { required property string modelData; required property int index
                                readonly property bool sel: w.mode === "money" ? modelData === (w.picker === "from" ? w.from : w.to) : index === (w.picker === "from" ? w.uFrom : w.uTo)
                                width: 56; height: 32; radius: 16; color: sel ? Theme.accent : p.chipFill
                                Text { anchors.centerIn: parent; text: modelData; textFormat: Text.PlainText; color: sel ? "#101218" : Theme.text
                                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: { if (w.mode === "money") { if (w.picker === "from") w.from = modelData; else w.to = modelData; }
                                                 else { if (w.picker === "from") w.uFrom = index; else w.uTo = index; }
                                                 w.picker = ""; } } } } } }
            }
        }
    }
}
