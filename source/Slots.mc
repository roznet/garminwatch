import Toybox.Complications;
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
    // Five charge levels, empty to full, kept consecutive so a level indexes from ICON_BATTERY_0
    ICON_BATTERY_0,
    ICON_BATTERY_25,
    ICON_BATTERY_50,
    ICON_BATTERY_75,
    ICON_BATTERY_100,
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

    // The native complication behind a slot, whose glance a press-and-hold opens.
    // UTC has no native complication, so that slot is not pressable.
    function complicationType(field as Number, sunriseNext as Boolean) as Complications.Type? {
        if (field == FIELD_TEMPERATURE) {
            return Complications.COMPLICATION_TYPE_CURRENT_TEMPERATURE;
        } else if (field == FIELD_SUN_EVENT) {
            return sunriseNext ? Complications.COMPLICATION_TYPE_SUNRISE : Complications.COMPLICATION_TYPE_SUNSET;
        } else if (field == FIELD_HEART_RATE) {
            return Complications.COMPLICATION_TYPE_HEART_RATE;
        } else if (field == FIELD_ALTITUDE) {
            return Complications.COMPLICATION_TYPE_ALTITUDE;
        } else if (field == FIELD_STEPS) {
            return Complications.COMPLICATION_TYPE_STEPS;
        } else if (field == FIELD_BATTERY_DAYS) {
            return Complications.COMPLICATION_TYPE_BATTERY;
        } else if (field == FIELD_PRESSURE) {
            return Complications.COMPLICATION_TYPE_SEA_LEVEL_PRESSURE;
        } else if (field == FIELD_DATE) {
            return Complications.COMPLICATION_TYPE_DATE;
        }
        return null;
    }
}
