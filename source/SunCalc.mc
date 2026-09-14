import Toybox.Activity;
import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Weather;

// Sunrise and sunset from the last known position, using the standard sunrise equation
// (accurate to about a minute). Computed at most once per day and cached in Storage.
// Never requests a GPS fix: only positions the watch already has are read.
class SunCalc {

    const STORAGE_KEY = "sun";
    const RETRY_MS = 600000;

    // Unix seconds, or null for polar day/night or no position yet
    var riseToday as Number? = null;
    var setToday as Number? = null;
    var riseTomorrow as Number? = null;
    var nextIsSunrise as Boolean = true;

    private var mDay as Number = -1;
    private var mLat as Float? = null;
    private var mLon as Float? = null;
    private var mLastAttempt as Number? = null;

    function initialize() {
        var cached = Application.Storage.getValue(STORAGE_KEY);
        if (cached instanceof Array && cached.size() == 6) {
            mDay = cached[0] as Number;
            riseToday = cached[1] as Number?;
            setToday = cached[2] as Number?;
            riseTomorrow = cached[3] as Number?;
            mLat = cached[4] as Float?;
            mLon = cached[5] as Float?;
        }
    }

    function updateIfNewDay() as Void {
        var today = Time.today().value();
        if (today == mDay) {
            return;
        }
        // Without a position, retry every RETRY_MS rather than on every refresh
        var timer = System.getTimer();
        var lastAttempt = mLastAttempt;
        if (lastAttempt != null && timer - lastAttempt < RETRY_MS) {
            return;
        }
        mLastAttempt = timer;

        var position = readPosition();
        if (position != null) {
            mLat = position[0];
            mLon = position[1];
        }
        var lat = mLat;
        var lon = mLon;
        if (lat == null || lon == null) {
            return;
        }

        var todayTimes = sunTimes(today, lat, lon);
        var tomorrowTimes = sunTimes(today + 86400, lat, lon);
        riseToday = todayTimes[0];
        setToday = todayTimes[1];
        riseTomorrow = tomorrowTimes[0];
        mDay = today;
        mLastAttempt = null;
        Application.Storage.setValue(STORAGE_KEY, [mDay, riseToday, setToday, riseTomorrow, lat, lon]);
        System.println("SunCalc: recomputed for day " + today + " at " + lat + "," + lon);
    }

    // Time of the next sun event after now; sets nextIsSunrise
    function nextEventTime(now as Number) as Number? {
        var rise = riseToday;
        var set = setToday;
        if (rise != null && now < rise) {
            nextIsSunrise = true;
            return rise;
        }
        if (set != null && now < set) {
            nextIsSunrise = false;
            return set;
        }
        nextIsSunrise = true;
        return riseTomorrow;
    }

    private function readPosition() as [Float, Float]? {
        var location = null;
        var activity = Activity.getActivityInfo();
        if (activity != null) {
            location = activity.currentLocation;
        }
        if (location == null) {
            var info = Position.getInfo();
            if (info.accuracy != Position.QUALITY_NOT_AVAILABLE) {
                location = info.position;
            }
        }
        if (location == null && Toybox has :Weather) {
            var conditions = Weather.getCurrentConditions();
            if (conditions != null) {
                location = conditions.observationLocationPosition;
            }
        }
        if (location == null) {
            return null;
        }
        var degrees = location.toDegrees();
        var lat = degrees[0].toFloat();
        var lon = degrees[1].toFloat();
        // 0,0 and out-of-range values mean the watch has never had a fix
        if ((lat == 0.0f && lon == 0.0f) || lat > 90.0f || lat < -90.0f) {
            return null;
        }
        return [lat, lon];
    }

    // [sunrise, sunset] in unix seconds for the local day starting at dayStart
    private function sunTimes(dayStart as Number, lat as Float, lon as Float) as [Number?, Number?] {
        // Doubles throughout: Julian dates need more precision than a Float holds
        var julianNoon = (dayStart + 43200).toDouble() / 86400.0d + 2440587.5d;
        var cycle = Math.ceil(julianNoon - 2451545.0d + 0.0008d);
        var meanSolarTime = cycle - lon.toDouble() / 360.0d;
        var anomaly = normalizeDegrees(357.5291d + 0.98560028d * meanSolarTime);
        var anomalyRad = Math.toRadians(anomaly);
        var centre = 1.9148d * Math.sin(anomalyRad) + 0.02d * Math.sin(2 * anomalyRad) + 0.0003d * Math.sin(3 * anomalyRad);
        var eclipticRad = Math.toRadians(normalizeDegrees(anomaly + centre + 180.0d + 102.9372d));
        var transit = 2451545.0d + meanSolarTime + 0.0053d * Math.sin(anomalyRad) - 0.0069d * Math.sin(2 * eclipticRad);
        var sinDeclination = Math.sin(eclipticRad) * Math.sin(Math.toRadians(23.4397d));
        var cosDeclination = Math.cos(Math.asin(sinDeclination));
        var latRad = Math.toRadians(lat.toDouble());
        var cosHourAngle = (Math.sin(Math.toRadians(-0.833d)) - Math.sin(latRad) * sinDeclination)
            / (Math.cos(latRad) * cosDeclination);
        if (cosHourAngle < -1 || cosHourAngle > 1) {
            return [null, null];
        }
        var halfDay = Math.toDegrees(Math.acos(cosHourAngle)) / 360.0d;
        return [julianToUnix(transit - halfDay), julianToUnix(transit + halfDay)];
    }

    private function normalizeDegrees(degrees as Double) as Double {
        return degrees - 360.0d * Math.floor(degrees / 360.0d);
    }

    private function julianToUnix(julian as Double) as Number {
        return ((julian - 2440587.5d) * 86400.0d).toNumber();
    }

}
