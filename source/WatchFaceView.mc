import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

module Colors {
    const TICK_ACCENT = 0xFF2020;
    const CENTRE_ACCENT = 0x22CCDD;
    const TEXT = 0xFFFFFF;
    // Icon tints, muted so the white values stay the loudest thing on the dial.
    // Colour costs nothing on AMOLED: a lit subpixel draws the power, and white lights all three.
    const ICON_DEFAULT = 0xFFFFFF;
    const ICON_THERMOMETER = 0xE08A3C;
    const ICON_SUNRISE = 0xE8C33A;
    const ICON_SUNSET = 0xD9702B;
    const ICON_HEART = 0xE03A3A;
    const ICON_MOUNTAIN = 0xA9764B;
    const ICON_STEPS = 0x7FC46A;
    const ICON_BATTERY = 0xBFC6CE;
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

    // Temperature icon colour scale, in Celsius
    // A pale neutral stop at 10C keeps the blend from cyan to yellow out of green
    const TEMPERATURE_STOPS = [-20, -5, 5, 10, 18, 25, 32, 40] as Array<Number>;
    const TEMPERATURE_COLORS = [0x4472E8, 0x4FA8E0, 0x8FD3E8, 0xDCD8C8, 0xE3D46B, 0xE8A33A, 0xE0662B, 0xD93A2B] as Array<Number>;

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
    private var mIconOptions as { :transform as AffineTransform, :filterMode as FilterMode, :tintColor as ColorType };

    // Tint per icon, indexed by IconId
    private var mIconColors as Array<Number>;

    // One colour per body segment, hub to tip
    private var mHourBodyColors as Array<Number>;
    private var mMinuteBodyColors as Array<Number>;

    // Complication types this watch publishes, so slots with no glance behind them stay inert
    private var mHasComplications as Boolean;
    private var mAvailableTypes as Dictionary<Number, Boolean>;

    function initialize() {
        WatchFace.initialize();
        mCanAntiAlias = Graphics.Dc has :setAntiAlias;
        mHasComplications = Toybox has :Complications;
        mAvailableTypes = {} as Dictionary<Number, Boolean>;
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
        mIconOptions = { :transform => mTransform, :filterMode => Graphics.FILTER_MODE_BILINEAR, :tintColor => Colors.ICON_DEFAULT };
        mIconColors = [
            Colors.ICON_THERMOMETER,
            Colors.ICON_SUNRISE,
            Colors.ICON_SUNSET,
            Colors.ICON_HEART,
            Colors.ICON_MOUNTAIN,
            Colors.ICON_STEPS,
            Colors.ICON_BATTERY,
            Colors.CENTRE_ACCENT
        ] as Array<Number>;
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

        findComplications();
    }

    // Record once which native complications exist on this watch, rather than assuming
    private function findComplications() as Void {
        if (!mHasComplications) {
            return;
        }
        var iterator = Complications.getComplications();
        var complication = iterator.next();
        while (complication != null) {
            var type = complication.getType();
            if (type != null) {
                mAvailableTypes.put(type, true);
            }
            complication = iterator.next();
        }
    }

    // The complication to open for a press at (x, y), or null when the press misses every slot,
    // the slot has no native complication (UTC), or this watch does not publish it
    function complicationAt(x as Number, y as Number) as Complications.Id? {
        var layout = mGeometry;
        if (layout == null || !mHasComplications) {
            return null;
        }
        var field = fieldAt(layout, x, y);
        if (field == null) {
            return null;
        }
        var type = Slots.complicationType(field, mData.isSunriseNext());
        if (type == null || !mAvailableTypes.hasKey(type)) {
            return null;
        }
        return new Complications.Id(type);
    }

    // Nearest slot within the touch radius, so overlapping targets resolve by distance
    private function fieldAt(layout as Layout, x as Number, y as Number) as Number? {
        var centres = layout.slotCentres;
        var limit = layout.touchRadius * layout.touchRadius;
        var best = null;
        var bestDistance = limit;
        for (var field = 0; field < centres.size(); field++) {
            var centre = centres[field];
            if (centre == null) {
                continue;
            }
            var dx = x - centre[0];
            var dy = y - centre[1];
            var distance = dx * dx + dy * dy;
            if (distance <= bestDistance) {
                best = field;
                bestDistance = distance;
            }
        }
        return best;
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
            drawIcon(dc, icon, layout.cx + r * Math.sin(theta), layout.cy - r * Math.cos(theta), rotation.toFloat(), iconColorFor(field));
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
            drawIcon(dc, icon, x, layout.centreLabelY, mData.iconRotations[field], iconColorFor(field));
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

    private function iconColorFor(field as Number) as Number {
        if (field == FIELD_TEMPERATURE) {
            var celsius = mData.temperatureCelsius;
            if (celsius != null) {
                return temperatureColor(celsius);
            }
        }
        var id = mData.icons[field];
        return id == ICON_NONE ? Colors.ICON_DEFAULT : mIconColors[id];
    }

    // Cold blue through to hot red, the ramp weather services use, without the green mid band
    // (the steps icon is already green). Stops are Celsius whatever unit is displayed.
    private function temperatureColor(celsius as Numeric) as Number {
        var stops = TEMPERATURE_STOPS;
        var colors = TEMPERATURE_COLORS;
        var last = stops.size() - 1;
        if (celsius <= stops[0]) {
            return colors[0];
        }
        if (celsius >= stops[last]) {
            return colors[last];
        }
        for (var i = 1; i <= last; i++) {
            if (celsius <= stops[i]) {
                var t = (celsius - stops[i - 1]).toFloat() / (stops[i] - stops[i - 1]);
                return blendChannel(colors[i - 1], colors[i], 16, t)
                    | blendChannel(colors[i - 1], colors[i], 8, t)
                    | blendChannel(colors[i - 1], colors[i], 0, t);
            }
        }
        return colors[last];
    }

    // Draw a bitmap centred on (x, y), rotated clockwise by rotation radians, in the given tint
    private function drawIcon(dc as Dc, icon as BitmapResource, x as Numeric, y as Numeric, rotation as Float, tint as Number) as Void {
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
        mIconOptions[:tintColor] = tint;
        dc.drawBitmap2(x, y, icon, mIconOptions);
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
