import QtQuick
import Quickshell.Io
import "../../core"

Tile {
    id: w
    implicitWidth: row.implicitWidth + 28
    readonly property real lat: config.lat ?? 51.51
    readonly property real lon: config.lon ?? -0.13
    readonly property string city: config.city ?? "London"
    property var wx: null
    readonly property bool ok: wx !== null && wx.current !== undefined
    function toggle() { pop.open = !pop.open; }
    onClicked: toggle()

    function icon(code, day) {
        if (code === 0) return day ? "clear_day" : "clear_night";
        if (code <= 2) return day ? "partly_cloudy_day" : "partly_cloudy_night";
        if (code === 3) return "cloud";
        if (code === 45 || code === 48) return "foggy";
        if (code >= 51 && code <= 57) return "rainy_light";
        if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return "rainy";
        if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "weather_snowy";
        if (code >= 95) return "thunderstorm";
        return "cloud";
    }
    function label(code) {
        if (code === 0) return "Clear"; if (code <= 2) return "Partly cloudy"; if (code === 3) return "Overcast";
        if (code === 45 || code === 48) return "Fog"; if (code >= 51 && code <= 57) return "Drizzle";
        if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return "Rain";
        if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "Snow"; if (code >= 95) return "Thunderstorm";
        return "Cloudy";
    }
    function hours() {
        if (!ok) return [];
        const h = wx.hourly, out = [], now = Date.now() - 3600000;
        let i = 0;
        while (i < h.time.length && new Date(h.time[i]).getTime() < now) i++;
        for (let k = i; k < h.time.length && out.length < 8; k += 3)
            out.push({ t: h.time[k].slice(11, 16), temp: Math.round(h.temperature_2m[k]), code: h.weather_code[k],
                       day: parseInt(h.time[k].slice(11, 13)) >= 7 && parseInt(h.time[k].slice(11, 13)) < 20 });
        return out;
    }
    function days() {
        if (!ok) return [];
        const d = wx.daily, out = [];
        for (let i = 0; i < Math.min(5, d.time.length); i++)
            out.push({ day: i === 0 ? "Today" : Qt.formatDate(new Date(d.time[i]), "ddd"), code: d.weather_code[i],
                       lo: Math.round(d.temperature_2m_min[i]), hi: Math.round(d.temperature_2m_max[i]) });
        return out;
    }

    Timer { interval: 900000; running: true; repeat: true; triggeredOnStart: true; onTriggered: fetch.running = true }
    Process {
        id: fetch
        command: ["curl", "-s", "--max-time", "8",
            "https://api.open-meteo.com/v1/forecast?latitude=" + w.lat + "&longitude=" + w.lon
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
            + "&hourly=temperature_2m,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset"
            + "&timezone=auto&forecast_days=5"]
        stdout: StdioCollector { onStreamFinished: { try { w.wx = JSON.parse(text); } catch (e) { } } }
    }

    Row {
        id: row
        anchors.centerIn: parent; spacing: 8
        Icon { anchors.verticalCenter: parent.verticalCenter; size: 28; color: Theme.accent
            name: w.ok ? w.icon(w.wx.current.weather_code, w.wx.current.is_day) : "cloud_off"
            SequentialAnimation on rotation { loops: Animation.Infinite; running: true
                NumberAnimation { to: 6; duration: 2600; easing.type: Easing.InOutSine }
                NumberAnimation { to: -6; duration: 2600; easing.type: Easing.InOutSine } } }
        Column { anchors.verticalCenter: parent.verticalCenter
            Text { text: w.ok ? Math.round(w.wx.current.temperature_2m) + "°" : "--"
                color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.Bold }
            Text { text: w.ok ? w.label(w.wx.current.weather_code) : "Loading"
                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10 } }
    }

    Popover {
        id: pop
        target: w
        panelWidth: 380
        panelHeight: 440
        Column {
            id: card
            anchors { fill: parent; margins: 16 }
            spacing: 14
            Row {   // hero
                spacing: 16; height: 84
                Icon { anchors.verticalCenter: parent.verticalCenter; size: 72; color: Theme.accent
                    name: w.ok ? w.icon(w.wx.current.weather_code, w.wx.current.is_day) : "cloud_off" }
                Column { anchors.verticalCenter: parent.verticalCenter
                    Text { text: w.ok ? Math.round(w.wx.current.temperature_2m) + "°" : "--"
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 46; font.weight: Font.DemiBold }
                    Text { text: w.ok ? w.label(w.wx.current.weather_code) + " · " + w.city : ""
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                    Text { text: w.ok ? "Feels like " + Math.round(w.wx.current.apparent_temperature) + "°" : ""
                        color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11 } }
            }
            Row {   // chips
                spacing: 8
                Repeater {
                    model: w.ok ? [ { i: "water_drop", v: Math.round(w.wx.current.relative_humidity_2m) + "%" },
                                    { i: "air", v: Math.round(w.wx.current.wind_speed_10m) + " km/h" },
                                    { i: "wb_twilight", v: w.wx.daily.sunrise[0].slice(11, 16) },
                                    { i: "bedtime", v: w.wx.daily.sunset[0].slice(11, 16) } ] : []
                    delegate: Rectangle {
                        required property var modelData
                        width: (card.width - 24) / 4; height: 34; radius: 17; color: Theme.tileFill
                        Row { anchors.centerIn: parent; spacing: 4
                            Icon { name: modelData.i; size: 14; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: modelData.v; color: Theme.text; font.family: Theme.font; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter } }
                    }
                }
            }
            Rectangle {   // hourly
                width: card.width; height: 92; radius: 14; color: Theme.tileFill
                Row { anchors { fill: parent; margins: 8 }
                    Repeater {
                        model: pop.open ? w.hours() : []
                        delegate: Column {
                            id: hcol
                            required property var modelData
                            required property int index
                            width: (card.width - 16) / 8; spacing: 4; opacity: 0
                            Component.onCompleted: fd.start()
                            SequentialAnimation { id: fd
                                PauseAnimation { duration: index * 45 }
                                NumberAnimation { target: hcol; property: "opacity"; to: 1; duration: 250 } }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: index === 0 ? "Now" : modelData.t
                                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 10 }
                            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: w.icon(modelData.code, modelData.day); size: 22; color: Theme.accent }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.temp + "°"
                                color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                        }
                    }
                }
            }
            Column {   // 5-day bars
                id: daily
                width: card.width; spacing: 6
                readonly property var list: w.days()
                readonly property real lo: Math.min.apply(null, list.map(d => d.lo).concat([99]))
                readonly property real hi: Math.max.apply(null, list.map(d => d.hi).concat([-99]))
                Repeater {
                    model: daily.list
                    delegate: Item {
                        required property var modelData
                        width: daily.width; height: 26
                        Text { width: 50; anchors.verticalCenter: parent.verticalCenter; text: modelData.day
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                        Icon { x: 54; anchors.verticalCenter: parent.verticalCenter; name: w.icon(modelData.code, true); size: 18; color: Theme.accent }
                        Text { x: 82; width: 28; anchors.verticalCenter: parent.verticalCenter; text: modelData.lo + "°"
                            color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                        Rectangle { id: track; x: 114; width: parent.width - 114 - 34; height: 6; radius: 3
                            anchors.verticalCenter: parent.verticalCenter; color: Theme.tileFill
                            Rectangle { height: 6; radius: 3; color: Theme.accent
                                readonly property real span: Math.max(1, daily.hi - daily.lo)
                                x: (modelData.lo - daily.lo) / span * track.width
                                width: pop.open ? Math.max(8, (modelData.hi - modelData.lo) / span * track.width) : 0
                                Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } } } }
                        Text { anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: modelData.hi + "°"
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                    }
                }
            }
        }
    }
}
