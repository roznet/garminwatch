import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;

// Reads every field from the system and keeps display strings ready, so onUpdate only draws.
// Each field has one null-safe function returning a string; missing data shows PLACEHOLDER.
class DataProvider {

    const PLACEHOLDER = "--";
    const REFRESH_MS = 5000;
    const TREND_REFRESH_MS = 600000;
    const TREND_WINDOW_S = 10800;
    const TREND_MIN_SPAN_S = 3600;
    const TREND_THRESHOLD_PA = 100;

    // Indexed by FieldId
    var values as Array<String>;
    var icons as Array<Number>;
    var labels as Array<String?>;
    var iconRotations as Array<Float>;

    private var mSun as SunCalc;
    private var mLastMinute as Number = -1;
    private var mLastRefresh as Number = 0;
    private var mLastTrend as Number? = null;

    private var mHasHeartRateHistory as Boolean;
    private var mHasPressureHistory as Boolean;
    private var mHasWeather as Boolean;

    function initialize() {
        mSun = new SunCalc();
        mHasHeartRateHistory = ActivityMonitor has :getHeartRateHistory;
        mHasPressureHistory = (Toybox has :SensorHistory) && (SensorHistory has :getPressureHistory);
        mHasWeather = Toybox has :Weather;

        values = new [FIELD_COUNT] as Array<String>;
        labels = new [FIELD_COUNT] as Array<String?>;
        iconRotations = new [FIELD_COUNT] as Array<Float>;
        for (var i = 0; i < FIELD_COUNT; i++) {
            values[i] = PLACEHOLDER;
            iconRotations[i] = 0.0f;
        }
        icons = [ICON_THERMOMETER, ICON_SUNRISE, ICON_HEART, ICON_MOUNTAIN, ICON_STEPS, ICON_BATTERY,
            ICON_NONE, ICON_NONE, ICON_NONE] as Array<Number>;
        labels[FIELD_UTC_TIME] = "UTC";
    }

    // Re-read everything when the minute changes, and at most every REFRESH_MS while awake
    function refreshIfDue(clock as System.ClockTime) as Void {
        var timer = System.getTimer();
        if (clock.min == mLastMinute && timer - mLastRefresh < REFRESH_MS) {
            return;
        }
        mLastMinute = clock.min;
        mLastRefresh = timer;

        var settings = System.getDeviceSettings();
        var activity = Activity.getActivityInfo();
        var now = Time.now();

        values[FIELD_TEMPERATURE] = temperature(settings);
        values[FIELD_SUN_EVENT] = sunEvent(now, settings);
        values[FIELD_HEART_RATE] = heartRate(activity);
        values[FIELD_ALTITUDE] = altitude(activity, settings);
        values[FIELD_STEPS] = steps();
        values[FIELD_BATTERY_DAYS] = batteryDays();
        values[FIELD_UTC_TIME] = utcTime(now);
        values[FIELD_PRESSURE] = pressure(activity);
        values[FIELD_DATE] = date(now);

        var lastTrend = mLastTrend;
        if (lastTrend == null || timer - lastTrend >= TREND_REFRESH_MS) {
            mLastTrend = timer;
            updatePressureTrend(now);
        }
    }

    // Which sun event the slot is showing, so a press opens the matching glance
    function isSunriseNext() as Boolean {
        return mSun.nextIsSunrise;
    }

    private function temperature(settings as System.DeviceSettings) as String {
        if (!mHasWeather) {
            return PLACEHOLDER;
        }
        var conditions = Weather.getCurrentConditions();
        if (conditions == null || conditions.temperature == null) {
            return PLACEHOLDER;
        }
        var celsius = conditions.temperature as Numeric;
        var shown = settings.temperatureUnits == System.UNIT_STATUTE ? celsius * 9 / 5.0f + 32 : celsius;
        return Math.round(shown).toNumber().toString() + "°";
    }

    private function sunEvent(now as Time.Moment, settings as System.DeviceSettings) as String {
        mSun.update();
        var eventTime = mSun.nextEventTime(now.value());
        icons[FIELD_SUN_EVENT] = mSun.nextIsSunrise ? ICON_SUNRISE : ICON_SUNSET;
        if (eventTime == null) {
            return PLACEHOLDER;
        }
        var info = Gregorian.info(new Time.Moment(eventTime), Time.FORMAT_SHORT);
        var hour = info.hour;
        if (!settings.is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        return hour.toString() + ":" + info.min.format("%02d");
    }

    private function heartRate(activity as Activity.Info?) as String {
        var hr = activity != null ? activity.currentHeartRate : null;
        if (hr == null && mHasHeartRateHistory) {
            var sample = ActivityMonitor.getHeartRateHistory(1, true).next();
            if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                hr = sample.heartRate;
            }
        }
        return hr == null ? PLACEHOLDER : hr.toString();
    }

    private function altitude(activity as Activity.Info?, settings as System.DeviceSettings) as String {
        var metres = activity != null ? activity.altitude : null;
        if (metres == null) {
            return PLACEHOLDER;
        }
        var shown = settings.elevationUnits == System.UNIT_STATUTE ? metres * 3.28084f : metres;
        return Math.round(shown).toNumber().toString();
    }

    private function steps() as String {
        var count = ActivityMonitor.getInfo().steps;
        return count == null ? PLACEHOLDER : count.toString();
    }

    private function batteryDays() as String {
        return System.getSystemStats().batteryInDays.toNumber().toString() + "d";
    }

    private function utcTime(now as Time.Moment) as String {
        var utc = Gregorian.utcInfo(now, Time.FORMAT_SHORT);
        return utc.hour.format("%02d") + ":" + utc.min.format("%02d");
    }

    private function pressure(activity as Activity.Info?) as String {
        var pascals = activity != null ? activity.meanSeaLevelPressure : null;
        if (pascals == null) {
            return PLACEHOLDER;
        }
        return (pascals / 100 + 0.5f).toNumber().toString();
    }

    private function date(now as Time.Moment) as String {
        var info = Gregorian.info(now, Time.FORMAT_MEDIUM);
        return (info.day_of_week as String).toUpper() + " " + info.day.toString();
    }

    // Rising / steady / falling from the oldest and newest samples in the trend window.
    // The pressure icon is hidden when there is not enough history (e.g. after a power cycle).
    private function updatePressureTrend(now as Time.Moment) as Void {
        icons[FIELD_PRESSURE] = ICON_NONE;
        if (!mHasPressureHistory) {
            return;
        }
        var newest = SensorHistory.getPressureHistory({ :period => 1 }).next();
        var oldest = SensorHistory.getPressureHistory({
            :period => new Time.Duration(TREND_WINDOW_S),
            :order => SensorHistory.ORDER_OLDEST_FIRST
        }).next();
        if (newest == null || oldest == null || newest.data == null || oldest.data == null) {
            return;
        }
        var oldestTime = oldest.when;
        if (oldestTime == null || now.value() - oldestTime.value() < TREND_MIN_SPAN_S) {
            return;
        }
        var change = (newest.data as Numeric) - (oldest.data as Numeric);
        var rotation = 0.0f;
        if (change > TREND_THRESHOLD_PA) {
            rotation = (-Math.PI / 4).toFloat();
        } else if (change < -TREND_THRESHOLD_PA) {
            rotation = (Math.PI / 4).toFloat();
        }
        icons[FIELD_PRESSURE] = ICON_TREND;
        iconRotations[FIELD_PRESSURE] = rotation;
    }

}
