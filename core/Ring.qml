import QtQuick

// Circular progress ring: <Ring size={22} value={0..1} color=.../>
Item {
    id: ring
    property real size: 22
    property real thickness: 3
    property real value: 0
    property bool endDot: false     // bright dot at the arc end (battery-style)
    property color fill: Theme.accent
    property color track: Qt.rgba(1, 1, 1, 0.14)
    width: size; height: size
    property real shown: value
    Behavior on shown { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
    onShownChanged: cv.requestPaint()
    onFillChanged: cv.requestPaint()
    onEndDotChanged: cv.requestPaint()
    Canvas {
        id: cv
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            const c = getContext("2d"); c.reset();
            const r = (width - ring.thickness) / 2, cx = width / 2, cy = height / 2;
            c.lineWidth = ring.thickness; c.lineCap = "round";
            c.strokeStyle = ring.track; c.beginPath(); c.arc(cx, cy, r, 0, Math.PI * 2); c.stroke();
            if (ring.shown > 0.001) {
                c.strokeStyle = ring.fill; c.beginPath();
                c.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.min(1, ring.shown)); c.stroke();
                if (ring.endDot) {
                    const a = -Math.PI / 2 + Math.PI * 2 * Math.min(1, ring.shown);
                    c.fillStyle = "rgba(255,255,255,0.95)"; c.beginPath();
                    c.arc(cx + r * Math.cos(a), cy + r * Math.sin(a), ring.thickness * 0.32, 0, Math.PI * 2); c.fill();
                }
            }
        }
    }
}
