import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// Resolution-independent geometry, computed once from the screen size.
// Lengths are fractions of the dial radius, widths fractions of the screen size.
class Layout {

    const RING_RADIUS = 0.78;

    const TICK_COUNT = 6;
    const TICK_INNER = 0.70;
    const TICK_OUTER = 0.84;
    const TICK_THICKNESS = 0.018;

    const HOUR_LENGTH = 0.55;
    const MINUTE_LENGTH = 0.80;
    const HAND_BASE_WIDTH = 0.008;
    const HAND_TIP_WIDTH = 0.0045;
    const HAND_OUTLINE = 0.0022;

    const SECOND_LENGTH = 0.88;
    const SECOND_TIP_LENGTH = 0.08;
    const SECOND_WIDTH = 0.006;

    const HUB_RADIUS = 0.013;

    var cx as Float;
    var cy as Float;
    var radius as Float;
    var ringRadius as Float;

    // Tick bars, already in screen coordinates
    var ticks as Array<Array<Point2D>>;

    // Hand shapes pointing at 12 o'clock, relative to the centre.
    // Each outline shape is the hand grown by the outline width, filled black underneath.
    var hourShape as Array<Point2D>;
    var hourOutline as Array<Point2D>;
    var minuteShape as Array<Point2D>;
    var minuteOutline as Array<Point2D>;

    var secondLength as Float;
    var secondTipStart as Float;
    var secondPenWidth as Number;
    var hubRadius as Float;

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

        var outline = size * HAND_OUTLINE;
        if (outline < 1.0f) {
            outline = 1.0f;
        }
        var base = size * HAND_BASE_WIDTH;
        var tip = size * HAND_TIP_WIDTH;
        hourShape = taperedHand(radius * HOUR_LENGTH, base, tip, 0.0f);
        hourOutline = taperedHand(radius * HOUR_LENGTH, base, tip, outline);
        minuteShape = taperedHand(radius * MINUTE_LENGTH, base, tip, 0.0f);
        minuteOutline = taperedHand(radius * MINUTE_LENGTH, base, tip, outline);

        secondLength = radius * SECOND_LENGTH;
        secondTipStart = radius * (SECOND_LENGTH - SECOND_TIP_LENGTH);
        secondPenWidth = (size * SECOND_WIDTH + 0.5f).toNumber();
        if (secondPenWidth < 2) {
            secondPenWidth = 2;
        }
        hubRadius = radius * HUB_RADIUS * 2;
    }

    private function taperedHand(length as Float, baseWidth as Float, tipWidth as Float, grow as Float) as Array<Point2D> {
        var b = baseWidth / 2 + grow;
        var t = tipWidth / 2 + grow;
        return [[-b, grow], [-t, -length - grow], [t, -length - grow], [b, grow]] as Array<Point2D>;
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
