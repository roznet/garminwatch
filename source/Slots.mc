import Toybox.Lang;

// Every field the face can show. FIELD_COUNT sizes the per-field arrays.
enum FieldId {
    FIELD_TEMPERATURE,
    FIELD_SUN_EVENT,
    FIELD_HEART_RATE,
    FIELD_ALTITUDE,
    FIELD_STEPS,
    FIELD_BATTERY_DAYS,
    FIELD_UTC_TIME,
    FIELD_PRESSURE,
    FIELD_DATE,
    FIELD_COUNT
}

// Icon bitmaps, in the order WatchFaceView loads them
enum IconId {
    ICON_NONE = -1,
    ICON_THERMOMETER,
    ICON_SUNRISE,
    ICON_SUNSET,
    ICON_HEART,
    ICON_MOUNTAIN,
    ICON_STEPS,
    ICON_BATTERY,
    ICON_TREND,
    ICON_COUNT
}

// Phase 1 slot assignments (spec section 11)
module Slots {
    // Ring slots clockwise from 1 o'clock; anchor angles are computed from the count
    const RING = [FIELD_TEMPERATURE, FIELD_SUN_EVENT, FIELD_HEART_RATE, FIELD_ALTITUDE, FIELD_STEPS, FIELD_BATTERY_DAYS] as Array<Number>;
    const CENTRE_LEFT = FIELD_UTC_TIME;
    const CENTRE_RIGHT = FIELD_PRESSURE;
    const CENTRE_BOTTOM = FIELD_DATE;
}
