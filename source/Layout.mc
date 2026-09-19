import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// Resolution-independent geometry, computed once from the screen size.
// Lengths are fractions of the dial radius, widths and font sizes fractions of the screen size,
// and centre positions fractions of screen width (x) or height (y).
class Layout {

    const RING_RADIUS = 0.78;

    const TICK_COUNT = 6;
    const TICK_INNER = 0.70;
    const TICK_OUTER = 0.84;
    const TICK_THICKNESS = 0.018;

    const HOUR_LENGTH = 0.55;
    const MINUTE_LENGTH = 0.80;
    const HAND_BASE_WIDTH = 0.020;
    const HAND_TIP_WIDTH = 0.007;
    const HAND_OUTLINE = 0.0022;
    // White rim around the tinted body, and where the body starts (fraction of hand length).
    // Keep the rim thin: it eats into the body from both sides, and a wide rim makes the hand
    // read as a hollow outline.
    const HAND_RIM = 0.0022;
    const HAND_BODY_START = 0.10;
    const HAND_BODY_SEGMENTS = 8;

    const SECOND_LENGTH = 0.88;
    const SECOND_TIP_LENGTH = 0.08;
    const SECOND_WIDTH = 0.006;

    const HUB_RADIUS = 0.013;

    // Touch targets are far bigger than the drawn slot: 0.075 of the screen is a ~68px box at 454px
    const TOUCH_RADIUS = 0.075;

    // Ring slots span 1 o'clock to 11 o'clock, leaving 12 clear
    const SLOT_FIRST_ANGLE = 30.0f;
    const SLOT_LAST_ANGLE = 330.0f;
    const SLOT_GAP = 0.014;
    // Ring text has to fit between two ticks: at 60 degrees apart on the ring radius that is
    // about 175px of arc at 454px, and the longest values ("20:07") take ~150px with their icon.
    const RING_FONT_SIZE = 0.088;

    // Centre columns sit wide enough that the bigger values clear the divider
    const CENTRE_LEFT_X = 0.34;
    const CENTRE_RIGHT_X = 0.66;
    const CENTRE_LABEL_Y = 0.25;
    const CENTRE_VALUE_Y = 0.35;
    const CENTRE_LABEL_FONT_SIZE = 0.060;
    const CENTRE_VALUE_FONT_SIZE = 0.100;
    const DIVIDER_TOP = 0.22;
    const DIVIDER_BOTTOM = 0.40;
    const DIVIDER_WIDTH = 0.004;
    const DATE_Y = 0.70;
    const DATE_FONT_SIZE = 0.105;

    const FONT_FACES = ["RobotoCondensedBold", "RobotoRegular"] as Array<String>;

    var cx as Float;
    var cy as Float;
    var radius as Float;
    var ringRadius as Float;

    // Tick bars, already in screen coordinates
    var ticks as Array<Array<Point2D>>;

    // Hand shapes pointing at 12 o'clock, relative to the centre: a black outline (the hand grown
    // by the outline width), the white rim shape, and the tinted body split into segments so it
    // can be drawn as a stepped gradient from hub to tip.
    var hourOutline as Array<Point2D>;
    var hourShape as Array<Point2D>;
    var hourBody as Array<Array<Point2D>>;
    var minuteOutline as Array<Point2D>;
    var minuteShape as Array<Point2D>;
    var minuteBody as Array<Array<Point2D>>;

    var secondLength as Float;
    var secondTipStart as Float;
    var secondPenWidth as Number;
    var hubRadius as Float;

    // Clock angle in degrees (0 = 12 o'clock, clockwise) of each ring slot anchor
    var ringAngles as Array<Float>;
    var slotGap as Float;

    // Centre of each field's touch target, indexed by FieldId; null for fields with no slot
    var slotCentres as Array<Point2D?>;
    var touchRadius as Float;

    var centreLeftX as Float;
    var centreRightX as Float;
    var centreLabelY as Float;
    var centreValueY as Float;
    var dividerTop as Float;
    var dividerBottom as Float;
    var dividerWidth as Number;
    var dateY as Float;

    var ringFont as VectorFont?;
    var centreLabelFont as VectorFont?;
    var centreValueFont as VectorFont?;
    var dateFont as VectorFont?;

    function initialize(width as Number, height as Number) {
        var size = (width < height ? width : height).toFloat();
        cx = width / 2.0f;
        cy = height / 2.0f;
        radius = size / 2.0f;
        ringRadius = radius * RING_RADIUS;

        var halfThick = size * TICK_THICKNESS / 2.0f;
        var inner = radius * TICK_INNER;
        var outer = radius * TICK_OUTER;
        var bar = [[-halfThick, -inner], [-halfThick, -outer], [halfThick, -outer], [halfThick, -inner]] as Array<Point2D>;
        ticks = [] as Array<Array<Point2D>>;
        for (var i = 0; i < TICK_COUNT; i++) {
            var tick = newPolygon(bar.size());
            rotatePoints(bar, tick, (2 * Math.PI * i / TICK_COUNT).toFloat(), cx, cy);
            ticks.add(tick);
        }

        var outline = atLeastFloat(size * HAND_OUTLINE, 1.0f);
        var rim = atLeastFloat(size * HAND_RIM, 1.0f);
        var base = size * HAND_BASE_WIDTH;
        var tip = size * HAND_TIP_WIDTH;
        hourOutline = taperedHand(radius * HOUR_LENGTH, base, tip, outline);
        hourShape = taperedHand(radius * HOUR_LENGTH, base, tip, 0.0f);
        hourBody = handBody(radius * HOUR_LENGTH, base, tip, rim);
        minuteOutline = taperedHand(radius * MINUTE_LENGTH, base, tip, outline);
        minuteShape = taperedHand(radius * MINUTE_LENGTH, base, tip, 0.0f);
        minuteBody = handBody(radius * MINUTE_LENGTH, base, tip, rim);

        secondLength = radius * SECOND_LENGTH;
        secondTipStart = radius * (SECOND_LENGTH - SECOND_TIP_LENGTH);
        secondPenWidth = atLeast((size * SECOND_WIDTH + 0.5f).toNumber(), 2);
        hubRadius = size * HUB_RADIUS;

        var count = Slots.RING.size();
        ringAngles = new [count] as Array<Float>;
        for (var i = 0; i < count; i++) {
            ringAngles[i] = count > 1
                ? SLOT_FIRST_ANGLE + (SLOT_LAST_ANGLE - SLOT_FIRST_ANGLE) * i / (count - 1)
                : 180.0f;
        }
        slotGap = size * SLOT_GAP;

        centreLeftX = width * CENTRE_LEFT_X;
        centreRightX = width * CENTRE_RIGHT_X;
        centreLabelY = height * CENTRE_LABEL_Y;
        centreValueY = height * CENTRE_VALUE_Y;
        dividerTop = height * DIVIDER_TOP;
        dividerBottom = height * DIVIDER_BOTTOM;
        dividerWidth = atLeast((size * DIVIDER_WIDTH + 0.5f).toNumber(), 1);
        dateY = height * DATE_Y;

        touchRadius = size * TOUCH_RADIUS;
        slotCentres = new [FIELD_COUNT] as Array<Point2D?>;
        for (var i = 0; i < count; i++) {
            var theta = Math.toRadians(ringAngles[i]);
            slotCentres[Slots.RING[i]] = [cx + ringRadius * Math.sin(theta), cy - ringRadius * Math.cos(theta)];
        }
        var centreRowY = (centreLabelY + centreValueY) / 2;
        slotCentres[Slots.CENTRE_LEFT] = [centreLeftX, centreRowY];
        slotCentres[Slots.CENTRE_RIGHT] = [centreRightX, centreRowY];
        slotCentres[Slots.CENTRE_BOTTOM] = [cx, dateY];

        ringFont = vectorFont(size * RING_FONT_SIZE);
        centreLabelFont = vectorFont(size * CENTRE_LABEL_FONT_SIZE);
        centreValueFont = vectorFont(size * CENTRE_VALUE_FONT_SIZE);
        dateFont = vectorFont(size * DATE_FONT_SIZE);
    }

    private function taperedHand(length as Float, baseWidth as Float, tipWidth as Float, grow as Float) as Array<Point2D> {
        var b = baseWidth / 2 + grow;
        var t = tipWidth / 2 + grow;
        return [[-b, grow], [-t, -length - grow], [t, -length - grow], [b, grow]] as Array<Point2D>;
    }

    // The hand inset by the rim, from HAND_BODY_START to just short of the tip, cut into segments.
    // Segments overlap by half a pixel so anti-aliasing leaves no seams between them.
    private function handBody(length as Float, baseWidth as Float, tipWidth as Float, rim as Float) as Array<Array<Point2D>> {
        var segments = [] as Array<Array<Point2D>>;
        var start = length * HAND_BODY_START;
        var end = length - rim * 2;
        for (var i = 0; i < HAND_BODY_SEGMENTS; i++) {
            var near = start + (end - start) * i / HAND_BODY_SEGMENTS;
            var far = start + (end - start) * (i + 1) / HAND_BODY_SEGMENTS;
            if (i < HAND_BODY_SEGMENTS - 1) {
                far += 0.5f;
            }
            var nearHalf = bodyHalfWidth(near, length, baseWidth, tipWidth, rim);
            var farHalf = bodyHalfWidth(far, length, baseWidth, tipWidth, rim);
            segments.add([[-nearHalf, -near], [-farHalf, -far], [farHalf, -far], [nearHalf, -near]] as Array<Point2D>);
        }
        return segments;
    }

    private function bodyHalfWidth(distance as Float, length as Float, baseWidth as Float, tipWidth as Float, rim as Float) as Float {
        var half = (baseWidth + (tipWidth - baseWidth) * distance / length) / 2 - rim;
        return atLeastFloat(half, 0.0f);
    }

    private function vectorFont(pixels as Float) as VectorFont? {
        return Graphics.getVectorFont({ :face => FONT_FACES, :size => (pixels + 0.5f).toNumber() });
    }

    private function atLeast(value as Number, minimum as Number) as Number {
        return value < minimum ? minimum : value;
    }

    private function atLeastFloat(value as Float, minimum as Float) as Float {
        return value < minimum ? minimum : value;
    }

}

// Allocate a polygon once so it can be rewritten in place on every draw.
function newPolygon(count as Number) as Array<Point2D> {
    var points = new [count] as Array<Point2D>;
    for (var i = 0; i < count; i++) {
        points[i] = [0.0f, 0.0f];
    }
    return points;
}

// Rotate src clockwise by angle (radians, 0 = 12 o'clock) around the origin,
// translate to (cx, cy), and write the result into dst without allocating.
function rotatePoints(src as Array<Point2D>, dst as Array<Point2D>, angle as Float, cx as Float, cy as Float) as Void {
    var c = Math.cos(angle);
    var s = Math.sin(angle);
    for (var i = 0; i < src.size(); i++) {
        var x = src[i][0];
        var y = src[i][1];
        dst[i][0] = cx + x * c - y * s;
        dst[i][1] = cy + x * s + y * c;
    }
}
