import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

module Colors {
    const TICK_ACCENT = 0xFF2020;
    const HOUR_HAND = 0xAAAAAA;
    const MINUTE_HAND = 0xFFFFFF;
    const SECOND_HAND = 0xFF2020;
    const SECOND_TIP = 0xFFFFFF;
    const HUB = 0xAAAAAA;
}

class WatchFaceView extends WatchUi.WatchFace {

    // How long the second hand keeps ticking after the watch wakes up
    const SECOND_HAND_DURATION_MS = 60000;

    private var mGeometry as Layout?;
    private var mCanAntiAlias as Boolean;
    private var mAwake as Boolean = true;
    private var mWakeTimer as Number;

    // Reused every draw so onUpdate does not allocate polygons
    private var mHourPts as Array<Point2D>;
    private var mHourOutlinePts as Array<Point2D>;
    private var mMinutePts as Array<Point2D>;
    private var mMinuteOutlinePts as Array<Point2D>;

    function initialize() {
        WatchFace.initialize();
        mCanAntiAlias = Graphics.Dc has :setAntiAlias;
        mWakeTimer = System.getTimer();
        mHourPts = newPolygon(4);
        mHourOutlinePts = newPolygon(4);
        mMinutePts = newPolygon(4);
        mMinuteOutlinePts = newPolygon(4);
    }

    function onLayout(dc as Dc) as Void {
        mGeometry = new Layout(dc.getWidth(), dc.getHeight());
    }

    function onShow() as Void {
        mWakeTimer = System.getTimer();
    }

    function onUpdate(dc as Dc) as Void {
        var layout = mGeometry;
        if (layout == null) {
            return;
        }
        if (mCanAntiAlias) {
            dc.setAntiAlias(true);
        }

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        drawTicks(dc, layout);

        // Data slots go here, between the ticks and the hands

        var clock = System.getClockTime();
        var minutes = clock.min + clock.sec / 60.0f;
        var hourAngle = (((clock.hour % 12) + minutes / 60.0f) * Math.PI / 6).toFloat();
        var minuteAngle = (minutes * Math.PI / 30).toFloat();

        drawHand(dc, layout, layout.hourOutline, mHourOutlinePts, layout.hourShape, mHourPts, hourAngle, Colors.HOUR_HAND);
        drawHand(dc, layout, layout.minuteOutline, mMinuteOutlinePts, layout.minuteShape, mMinutePts, minuteAngle, Colors.MINUTE_HAND);

        if (mAwake && System.getTimer() - mWakeTimer < SECOND_HAND_DURATION_MS) {
            drawSecondHand(dc, layout, (clock.sec * Math.PI / 30).toFloat());
        }

        dc.setColor(Colors.HUB, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(layout.cx, layout.cy, layout.hubRadius);
    }

    function onExitSleep() as Void {
        mAwake = true;
        mWakeTimer = System.getTimer();
    }

    function onEnterSleep() as Void {
        mAwake = false;
        WatchUi.requestUpdate();
    }

    private function drawTicks(dc as Dc, layout as Layout) as Void {
        dc.setColor(Colors.TICK_ACCENT, Graphics.COLOR_TRANSPARENT);
        var ticks = layout.ticks;
        for (var i = 0; i < ticks.size(); i++) {
            dc.fillPolygon(ticks[i]);
        }
    }

    // Black outline polygon first, hand on top, so the hand stays legible over text
    private function drawHand(dc as Dc, layout as Layout, outline as Array<Point2D>, outlinePts as Array<Point2D>,
            shape as Array<Point2D>, shapePts as Array<Point2D>, angle as Float, color as Number) as Void {
        rotatePoints(outline, outlinePts, angle, layout.cx, layout.cy);
        rotatePoints(shape, shapePts, angle, layout.cx, layout.cy);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(outlinePts);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(shapePts);
    }

    private function drawSecondHand(dc as Dc, layout as Layout, angle as Float) as Void {
        var dx = Math.sin(angle);
        var dy = -Math.cos(angle);
        dc.setPenWidth(layout.secondPenWidth);
        dc.setColor(Colors.SECOND_HAND, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(layout.cx, layout.cy, layout.cx + dx * layout.secondTipStart, layout.cy + dy * layout.secondTipStart);
        dc.setColor(Colors.SECOND_TIP, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(layout.cx + dx * layout.secondTipStart, layout.cy + dy * layout.secondTipStart,
            layout.cx + dx * layout.secondLength, layout.cy + dy * layout.secondLength);
    }

}
