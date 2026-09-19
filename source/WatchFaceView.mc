import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

module Colors {
    const TICK_ACCENT = 0xFF2020;
    const CENTRE_ACCENT = 0x22CCDD;
    const TEXT = 0xFFFFFF;
    const DIVIDER = 0xAAAAAA;
    const HAND_RIM = 0xFFFFFF;
    // Sand-tinted hand bodies, fading from the hub (NEAR) to the tip (FAR); the hour hand is darker
    const HOUR_BODY_NEAR = 0x8C7048;
    const HOUR_BODY_FAR = 0xD8BC8C;
    const MINUTE_BODY_NEAR = 0xA88554;
    const MINUTE_BODY_FAR = 0xF2E0BC;
    const SECOND_HAND = 0xFF2020;
    const SECOND_TIP = 0xFFFFFF;
    const HUB = 0xAAAAAA;
}

class WatchFaceView extends WatchUi.WatchFace {

    // How long the second hand keeps ticking after the watch wakes up
    const SECOND_HAND_DURATION_MS = 60000;

    const TEXT_CENTERED = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

    private var mGeometry as Layout?;
    private var mData as DataProvider;
    private var mCanAntiAlias as Boolean;
    private var mAwake as Boolean = true;
    private var mWakeTimer as Number;

    // Indexed by IconId, loaded once in onLayout
    private var mIcons as Array<BitmapResource?>;

    // Reused every draw so onUpdate does not allocate polygons or transforms
    private var mHourOutlinePts as Array<Point2D>;
    private var mHourPts as Array<Point2D>;
    private var mHourBodyPts as Array<Array<Point2D>>;
    private var mMinuteOutlinePts as Array<Point2D>;
    private var mMinutePts as Array<Point2D>;
    private var mMinuteBodyPts as Array<Array<Point2D>>;
    private var mTransform as AffineTransform;
    private var mMatrix as [Float, Float, Float, Float, Float, Float];
    private var mIconOptions as { :transform as AffineTransform, :filterMode as FilterMode };
    private var mTintedIconOptions as { :transform as AffineTransform, :filterMode as FilterMode, :tintColor as ColorType };

    // One colour per body segment, hub to tip
    private var mHourBodyColors as Array<Number>;
    private var mMinuteBodyColors as Array<Number>;

    function initialize() {
        WatchFace.initialize();
        mCanAntiAlias = Graphics.Dc has :setAntiAlias;
        mWakeTimer = System.getTimer();
        mData = new DataProvider();
        mIcons = new [ICON_COUNT] as Array<BitmapResource?>;
        mHourOutlinePts = newPolygon(4);
        mHourPts = newPolygon(4);
        mHourBodyPts = [] as Array<Array<Point2D>>;
        mMinuteOutlinePts = newPolygon(4);
        mMinutePts = newPolygon(4);
        mMinuteBodyPts = [] as Array<Array<Point2D>>;
        mHourBodyColors = [] as Array<Number>;
        mMinuteBodyColors = [] as Array<Number>;
        mTransform = new Graphics.AffineTransform();
        mMatrix = [1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f];
        mIconOptions = { :transform => mTransform, :filterMode => Graphics.FILTER_MODE_BILINEAR };
        mTintedIconOptions = { :transform => mTransform, :filterMode => Graphics.FILTER_MODE_BILINEAR, :tintColor => Colors.CENTRE_ACCENT };
    }

    function onLayout(dc as Dc) as Void {
        var layout = new Layout(dc.getWidth(), dc.getHeight());
        mGeometry = layout;
        mHourBodyPts = newPolygons(layout.hourBody.size());
        mMinuteBodyPts = newPolygons(layout.minuteBody.size());
        mHourBodyColors = gradient(Colors.HOUR_BODY_NEAR, Colors.HOUR_BODY_FAR, layout.hourBody.size());
        mMinuteBodyColors = gradient(Colors.MINUTE_BODY_NEAR, Colors.MINUTE_BODY_FAR, layout.minuteBody.size());

        var ids = [
            Rez.Drawables.IconThermometer,
            Rez.Drawables.IconSunrise,
            Rez.Drawables.IconSunset,
            Rez.Drawables.IconHeart,
            Rez.Drawables.IconMountain,
            Rez.Drawables.IconSteps,
            Rez.Drawables.IconBattery,
            Rez.Drawables.IconTrend
        ];
        for (var i = 0; i < ids.size(); i++) {
            mIcons[i] = WatchUi.loadResource(ids[i]) as BitmapResource;
        }
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

        var clock = System.getClockTime();
        if (mAwake) {
            mData.refreshIfDue(clock);
            drawRingSlots(dc, layout);
            drawCentre(dc, layout);
        }

        var minutes = clock.min + clock.sec / 60.0f;
        var hourAngle = (((clock.hour % 12) + minutes / 60.0f) * Math.PI / 6).toFloat();
        var minuteAngle = (minutes * Math.PI / 30).toFloat();

        drawHand(dc, layout, layout.hourOutline, mHourOutlinePts, layout.hourShape, mHourPts,
            layout.hourBody, mHourBodyPts, mHourBodyColors, hourAngle);
        drawHand(dc, layout, layout.minuteOutline, mMinuteOutlinePts, layout.minuteShape, mMinutePts,
            layout.minuteBody, mMinuteBodyPts, mMinuteBodyColors, minuteAngle);

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

    private function drawRingSlots(dc as Dc, layout as Layout) as Void {
        var font = layout.ringFont;
        if (font == null) {
            return;
        }
        var ring = Slots.RING;
        for (var i = 0; i < ring.size(); i++) {
            drawRingSlot(dc, layout, font, ring[i], layout.ringAngles[i]);
        }
    }

    // Icon (or label) followed by the value, laid along the ring and centred on the anchor angle.
    // Upper slots read clockwise; lower slots read counter-clockwise so the text stays upright.
    private function drawRingSlot(dc as Dc, layout as Layout, font as VectorFont, field as Number, anchor as Float) as Void {
        var value = mData.values[field];
        var icon = iconFor(field);
        var label = mData.labels[field];
        var r = layout.ringRadius;

        var leadWidth = 0;
        if (icon != null) {
            leadWidth = icon.getWidth();
        } else if (label != null) {
            leadWidth = dc.getTextWidthInPixels(label, font);
        }
        var gap = leadWidth > 0 ? layout.slotGap : 0.0f;
        var valueWidth = dc.getTextWidthInPixels(value, font);

        var clockwise = anchor <= 90 || anchor >= 270;
        var sign = clockwise ? 1 : -1;
        var degreesPerPixel = (180 / (Math.PI * r)).toFloat();
        var start = anchor - sign * (leadWidth + gap + valueWidth) / 2.0f * degreesPerPixel;
        var leadAngle = start + sign * leadWidth / 2.0f * degreesPerPixel;
        var valueAngle = start + sign * (leadWidth + gap + valueWidth / 2.0f) * degreesPerPixel;
        var direction = clockwise ? Graphics.RADIAL_TEXT_DIRECTION_CLOCKWISE : Graphics.RADIAL_TEXT_DIRECTION_COUNTER_CLOCKWISE;

        dc.setColor(Colors.TEXT, Graphics.COLOR_TRANSPARENT);
        if (icon != null) {
            var theta = Math.toRadians(leadAngle);
            var rotation = clockwise ? theta : theta + Math.PI;
            drawIcon(dc, icon, layout.cx + r * Math.sin(theta), layout.cy - r * Math.cos(theta), rotation.toFloat(), false);
        } else if (label != null) {
            dc.drawRadialText(layout.cx, layout.cy, font, label, TEXT_CENTERED, 90 - leadAngle, r, direction);
        }
        // drawRadialText angles are counter-clockwise from 3 o'clock
        dc.drawRadialText(layout.cx, layout.cy, font, value, TEXT_CENTERED, 90 - valueAngle, r, direction);
    }

    private function drawCentre(dc as Dc, layout as Layout) as Void {
        dc.setColor(Colors.DIVIDER, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(layout.dividerWidth);
        dc.drawLine(layout.cx, layout.dividerTop, layout.cx, layout.dividerBottom);

        drawCentreSlot(dc, layout, Slots.CENTRE_LEFT, layout.centreLeftX);
        drawCentreSlot(dc, layout, Slots.CENTRE_RIGHT, layout.centreRightX);

        var dateFont = layout.dateFont;
        if (dateFont != null) {
            dc.setColor(Colors.TEXT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(layout.cx, layout.dateY, dateFont, mData.values[Slots.CENTRE_BOTTOM], TEXT_CENTERED);
        }
    }

    // Accent icon (or label) above the value
    private function drawCentreSlot(dc as Dc, layout as Layout, field as Number, x as Float) as Void {
        var icon = iconFor(field);
        var label = mData.labels[field];
        var labelFont = layout.centreLabelFont;
        if (icon != null) {
            drawIcon(dc, icon, x, layout.centreLabelY, mData.iconRotations[field], true);
        } else if (label != null && labelFont != null) {
            dc.setColor(Colors.CENTRE_ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, layout.centreLabelY, labelFont, label, TEXT_CENTERED);
        }
        var valueFont = layout.centreValueFont;
        if (valueFont != null) {
            dc.setColor(Colors.TEXT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, layout.centreValueY, valueFont, mData.values[field], TEXT_CENTERED);
        }
    }

    private function iconFor(field as Number) as BitmapResource? {
        var id = mData.icons[field];
        return id == ICON_NONE ? null : mIcons[id];
    }

    // Draw a bitmap centred on (x, y), rotated clockwise by rotation radians
    private function drawIcon(dc as Dc, icon as BitmapResource, x as Numeric, y as Numeric, rotation as Float, tinted as Boolean) as Void {
        var halfWidth = icon.getWidth() / 2.0f;
        var halfHeight = icon.getHeight() / 2.0f;
        var c = Math.cos(rotation).toFloat();
        var s = Math.sin(rotation).toFloat();
        mMatrix[0] = c;
        mMatrix[1] = -s;
        mMatrix[2] = -(c * halfWidth - s * halfHeight);
        mMatrix[3] = s;
        mMatrix[4] = c;
        mMatrix[5] = -(s * halfWidth + c * halfHeight);
        mTransform.setMatrix(mMatrix);
        dc.drawBitmap2(x, y, icon, tinted ? mTintedIconOptions : mIconOptions);
    }

    // Black outline first so the hand stays legible over text, then the white rim shape,
    // then the tinted body segments on top as a stepped gradient from hub to tip
    private function drawHand(dc as Dc, layout as Layout, outline as Array<Point2D>, outlinePts as Array<Point2D>,
            shape as Array<Point2D>, shapePts as Array<Point2D>, body as Array<Array<Point2D>>,
            bodyPts as Array<Array<Point2D>>, bodyColors as Array<Number>, angle as Float) as Void {
        rotatePoints(outline, outlinePts, angle, layout.cx, layout.cy);
        rotatePoints(shape, shapePts, angle, layout.cx, layout.cy);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(outlinePts);
        dc.setColor(Colors.HAND_RIM, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(shapePts);
        for (var i = 0; i < body.size(); i++) {
            rotatePoints(body[i], bodyPts[i], angle, layout.cx, layout.cy);
            dc.setColor(bodyColors[i], Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon(bodyPts[i]);
        }
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

    private function newPolygons(count as Number) as Array<Array<Point2D>> {
        var polygons = new [count] as Array<Array<Point2D>>;
        for (var i = 0; i < count; i++) {
            polygons[i] = newPolygon(4);
        }
        return polygons;
    }

    // Linear blend between two RGB colours, one entry per step
    private function gradient(near as Number, far as Number, steps as Number) as Array<Number> {
        var colors = new [steps] as Array<Number>;
        for (var i = 0; i < steps; i++) {
            var t = steps > 1 ? i.toFloat() / (steps - 1) : 0.0f;
            colors[i] = blendChannel(near, far, 16, t) | blendChannel(near, far, 8, t) | blendChannel(near, far, 0, t);
        }
        return colors;
    }

    private function blendChannel(near as Number, far as Number, shift as Number, t as Float) as Number {
        var a = (near >> shift) & 0xFF;
        var b = (far >> shift) & 0xFF;
        return (a + (b - a) * t + 0.5f).toNumber() << shift;
    }

}
