# Minimal Analog Watch Face for Garmin Fenix 9 (AMOLED)

Specification for implementation. Target: Connect IQ watch face in Monkey C.

## 1. Intent

A deliberately plain analog watch face. Thin hands, no gradients, no decorative
graphics, no colour themes. Information density comes from small monochrome
icon plus number pairs, not from visual styling. The reference aesthetic is a
technical instrument panel, not a consumer smartwatch face.

Explicit non-goals:

- No web requests, no background process. Weather is limited to the current
  temperature the phone has already synced to the watch; the face never
  fetches weather itself
- No progress arcs, goal meters, move bars, or animated elements
- No colour beyond a few fixed accents (see section 11)
- No custom graphics beyond small monochrome icon bitmaps

The visual reference is `reference-concept.jpg` in this folder (kept locally,
not committed): follow its layout, but with icons instead of text labels and
solid instead of hollow hands.

## 2. Target device and prerequisites

- Device: Garmin Fenix 9 base model, AMOLED, round
- Always-on display: OFF (raise to wake). Design for the high-power layout
- Resolution: 416x416 (43mm), 454x454 (47mm and base 51mm), 466x466 (Pro 51mm
  only)
- Watch face memory limit: 131 KB (from the device profile)

**Device configurations (verified 2026-09-14, SDK 9.2.0):** there is no single
`fenix9` ID. The Fenix 9 IDs are `fenix943mm`, `fenix947mm` (base 47 and 51mm),
`fenix9pro47mm`, `fenix9pro51mm`, `fenix9prosolar47mm` and
`fenix9prosolar51mm`, all at API level 6.0.3. The manifest must list each one
explicitly: the compiler refuses to build for a device missing from it, and a
Fenix 8 build will not install on a Fenix 9.

**All geometry must be computed from `dc.getWidth()` and `dc.getHeight()` at
runtime.** No hardcoded pixel coordinates anywhere. Express every position as a
fraction of screen width or as a radius/angle pair. This is a hard requirement,
not a preference.

## 3. Layout

### 3.1 Dial

- Background: pure black `0x000000` (free pixels on AMOLED)
- Hour markers: 6 short, thick bars at 12, 2, 4, 6, 8 and 10 o'clock, drawn in
  the **tick accent colour** (red in `reference-concept.jpg`). The tick accent
  is its own colour, independent of any other accent, so it can later become a
  setting
- No minute ticks, no numerals on the dial
- Hands: hour, minute, and a thin **red second hand** with a short white tip,
  as in the reference photo
- Second hand behaviour: the Fenix 9 has no `onPartialUpdate` (the SDK docs
  list Fenix 8 but not Fenix 9), so it can only tick while the watch is awake.
  `onExitSleep` starts once-per-second updates and `onEnterSleep` drops to
  once-per-minute. Rules:
  - Record the time in `onExitSleep`; draw the second hand only while awake
    **and** for at most a fixed duration after waking (constant, default 60 s;
    a setting in phase 2). After that it disappears even if the watch is still
    awake
  - Never draw it after `onEnterSleep`
  - The watch firmware decides how long it stays awake; the face cannot extend
    that. Measure the real awake window on the watch
- Hand style: solid filled, thin tapered polygons, 3 to 4px at the base
  narrowing to 2px. Not the hollow outline hands of the reference photo.
  Hour hand ~55% of dial radius, minute hand ~80%
- Centre hub: small filled circle, ~6px radius
- `dc.setAntiAlias(true)` where supported, checked once at init

### 3.2 Data slots

Nine slots total. Each renders as a small icon glyph with a numeric value
beside or below it. Slot geometry is data-driven from a single configuration
array so slots can be added, removed, or reordered without touching layout code.

**Ring slots (5 or 6):** positioned on a circle at radius ~0.78 of half-width.
The count is a configuration parameter, not a constant, and anchor angles are
computed from it. For six, use the 1, 3, 5, 7, 9 and 11 o'clock angles, which
sit exactly between the six tick bars. For five, distribute
evenly across the lower 300 degrees leaving the 12 o'clock region open. Each slot
is an icon followed by its value, laid along the arc and centred on its anchor
angle. `reference-concept.jpg` shows the look, but with text labels (`BATT`,
`NOW`, `RISE`) where this face uses icons. The value is drawn with
`Dc.drawRadialText()` in a built-in vector font (`Graphics.getVectorFont`, e.g.
`RobotoCondensedBold`, present on `fenix947mm`). The icon is a bitmap rotated to
the arc with `Dc.drawBitmap2()` and an `AffineTransform`. Slots in the lower
half reverse direction so they read upright, left to right, as in the
reference.

**Centre slots (3):** two side by side in the upper half (roughly y = 0.34 of
height, at x = 0.33 and x = 0.67), one centred in the lower half (roughly
y = 0.68). The two upper slots render as icon over value, separated by a
thin vertical divider on the 12 o'clock axis. The lower slot (date) is value
only, in a larger size. Both follow `reference-concept.jpg`.

### 3.3 Draw order and hand legibility

The hands sweep over the three centre slots. Draw order must be:

1. Background
2. Tick marks
3. All nine data slots
4. Hour and minute hands, each filled shape stroked with a 1px black outline
5. Second hand (when shown), then the centre hub on top

The outline is what keeps the hands readable when they cross white text. Do not
skip it and do not solve this by moving the centre fields.

## 4. Data sources

All values come from standard system APIs. Nothing is reimplemented except the
sun times (see 4.1). No field may trigger a sensor wake, a GPS fix, or a
network call.

There are two routes to the same values, and the choice matters:

**Route A, direct reads.** `ActivityMonitor.getInfo()`, `System.getSystemStats()`,
`Activity.getActivityInfo()`. Simple, no permissions, no subscription lifecycle.
But a field read this way cannot be tapped to open a glance.

**Route B, the Complications API.** Subscribe to a native complication and
receive its value through a callback. Requires the `ComplicationSubscriber`
permission and a subscribe/unsubscribe lifecycle, but it is what makes
tap-to-glance possible (see 4.3).

**Default to Route B for any field that should be tappable**, which is most of
them. Use Route A only for fields with no matching native complication, such as
UTC time and the second timezone. The table below lists the Route A call for
each field as the fallback and for reference.

| Field | API | Notes |
|---|---|---|
| UTC time | `Time.Gregorian.utcInfo()` | Format `HH:MM`, always 24h |
| Second timezone | `Time.Gregorian.info()` with manual offset | Offset stored as a setting |
| Steps | `ActivityMonitor.getInfo().steps` | |
| Battery % | `System.getSystemStats().battery` | Round to integer |
| Battery days | `System.getSystemStats().batteryInDays` | |
| Altitude | `Activity.getActivityInfo().altitude` | Metres; convert per `elevationUnits`. Can be null. Complication: `COMPLICATION_TYPE_ALTITUDE` (Float since API 5.1) |
| Pressure (QNH) | `Activity.getActivityInfo().meanSeaLevelPressure` | **Pascals**, divide by 100 for hPa. Sea-level calibrated from GPS altitude, so it is the watch's QNH estimate, not an ATIS/METAR value. Do not use `ambientPressure` (station pressure). Complication: `COMPLICATION_TYPE_SEA_LEVEL_PRESSURE` |
| Pressure trend | `SensorHistory.getPressureHistory({:period => 3-hour Duration})` | Needs the `SensorHistory` permission. Compare newest vs oldest sample to get rising / steady / falling (threshold a tunable constant, start at ±1 hPa over 3 h). Recompute at most every 10 minutes, never inside `onUpdate()`. Samples are in pascals; history is lost on power cycle, so show steady/no arrow when too few samples |
| Heart rate | `Activity.getActivityInfo().currentHeartRate` | Can be null |
| Body Battery | Complications API | See section 4.2 |
| Weather temperature | `Weather.getCurrentConditions().temperature` | Celsius; convert per `temperatureUnits`. Reads conditions already synced from the phone, never fetches. Can be null (no phone sync yet). `observationTime` is available if stale data should be flagged. Complication: `COMPLICATION_TYPE_CURRENT_TEMPERATURE` (Float since API 5.0) |
| Temperature (wrist) | `Sensor.getInfo().temperature` | Wrist-heated, low value. Not used by default |
| Notifications | `System.getDeviceSettings().notificationCount` | |
| Phone connection | `System.getDeviceSettings().phoneConnected` | Icon only, no number |
| Sunrise / sunset | Computed, see 4.1 | |
| Date | `Time.Gregorian.info()` | |
| Floors climbed | `ActivityMonitor.getInfo().floorsClimbed` | |
| Distance | `ActivityMonitor.getInfo().distance` | cm, convert |
| Calories | `ActivityMonitor.getInfo().calories` | |

Every field must handle `null` gracefully by rendering a placeholder such as
`--`. Never let a null crash the draw path or the face becomes unusable until
reinstall.

### 4.1 Sunrise and sunset

Do **not** call `Position.getInfo()` on every update and do **not** request a
GPS fix. Implementation:

1. On init and on `onSettingsChanged`, read the cached last known position via
   `Position.getInfo()` once. This returns the last known fix without waking GPS
2. Compute sunrise and sunset locally using the NOAA solar position algorithm
   from latitude, longitude and date
3. Cache both results plus the date they were computed for, in `Storage`
4. Recompute only when the cached date no longer matches today's date

`Toybox.Weather.getSunrise()` is an alternative but depends on weather data
being present and synced, which is unreliable. Prefer the local computation.

The display should show the *next* sun event rather than both: sunrise if the
current time is before sunrise or after sunset, otherwise sunset, with the icon
distinguishing which.

### 4.2 Complications

Add `<uses-permission id="ComplicationSubscriber"/>` and
`<uses-permission id="SensorHistory"/>` (pressure trend) to the manifest.

Lifecycle: call `Complications.subscribeToUpdates()` for each active slot in
`onShow()`, and `Complications.unsubscribeFromAllUpdates()` in `onHide()`.
Never subscribe in `onUpdate()`. Values arrive via the registered callback and
should be cached in a field array that `onUpdate()` simply reads.

Use `Complications.getComplications()` at init to enumerate what the device
actually publishes, and degrade gracefully if an expected type is missing rather
than assuming availability.

Body Battery, sleep score, stress and similar derived metrics are **only**
available this way; there is no direct read for them.

### 4.3 Tap to open the native glance

Tapping a data slot should open the corresponding standard Garmin glance.

Implementation: a `WatchUi.WatchFaceDelegate` subclass overriding
`onPress(event as WatchUi.ClickEvent)`. Read `event.getCoordinates()`, hit-test
against the slot geometry computed in `Layout.mc`, and for a hit call
`Complications.exitTo(new Complications.Id(<the slot's complication type>))`
and return `true`. Return `false` on a miss so the system handles the tap
normally.

Known limitations, to be verified on the real watch rather than assumed:

- Only works on touch devices. The Fenix 9 has a touchscreen, so this is fine
- Only works for native complication types. A slot showing UTC time or a
  second timezone has no glance behind it and must be non-tappable
- Reports exist of `exitTo()` silently doing nothing for certain complication
  types on certain devices. Test every slot individually
- Does not work while a Connect IQ activity app is running in the background
  and the face is shown on top of it. This is platform behaviour, not a bug
  to fix

Hit-test regions should be generously sized, at least 60x60 pixels around each
slot anchor, since the rendered icon and number pair is much smaller than a
comfortable touch target. Overlapping regions must be resolved by nearest
anchor, not by array order.

## 5. Battery discipline

These are hard rules, not guidelines. A Connect IQ face runs in a VM and will
never quite match native firmware, but the gap should be a few percent, not a
visible daily loss. Everything below is a known cause of a visible loss.

- **No background process.** No `ServiceDelegate`, no `Background` registration
- **No `makeWebRequest`**, ever
- **No GPS requests.** Cached position only, read once
- **Read `Properties.getValue()` and `Storage.getValue()` only** in
  `initialize()` and `onSettingsChanged()`. Never in `onUpdate()`
- **No `loadResource()` inside `onUpdate()`.** Load fonts and icon resources
  once at init and keep references
- **No `has :` capability checks in `onUpdate()`.** Check once at init, store
  booleans
- **Cache anything expensive.** Sun times daily, tick mark coordinates once,
  pressure trend at most every 10 minutes
- **Second hand is time-limited.** Hidden after the fixed post-wake duration
  and always in sleep; no timers left running after `onEnterSleep`
- Precompute the tick mark and hand vertex geometry once into arrays at init,
  then only rotate at draw time
- Keep `onUpdate()` allocation-free where practical. Reuse arrays rather than
  creating new ones each call

The simulator's profiler and the Watch Face Diagnostics view should be used
during development, but they are not conclusive for AMOLED. Real validation is
wearing it for three days and comparing the battery curve against the stock
face over the same period.

## 6. Icon font

Garmin's built-in icons are not exposed through the Connect IQ API. They must be
recreated. Two APIs look like they might help and do not:

- `WatchFaceDelegate.getComplicationDrawable()` is a method the watch face
  *implements* so the system can highlight a slot during config editing. It
  does not return Garmin artwork
- `Complication.getIcon()` returns only icons published by third-party Connect
  IQ apps. Native complications return nothing

Build one small monochrome PNG bitmap per data type: footprint, battery,
mountain, barometer, heart, sun-up, sun-down, globe/UTC, flame, stairs, bell,
phone, thermometer. White on transparent, roughly 22px tall at 454px width.
Load all of them once at init.

Why bitmaps rather than a custom bitmap font: ring icons must rotate to follow
the arc. Custom font glyphs can only be drawn upright, and `drawRadialText()`
accepts only built-in vector fonts. `drawBitmap2()` takes an `AffineTransform`
for rotation and a `:tintColor`, so one white icon can be drawn in any accent
colour without extra resources. Check total bitmap memory against the 131 KB
watch face limit in the simulator.

Recommended generation path: draw the glyphs as SVG, rasterise, and use the
Connect IQ font generation workflow or a third party bitmap font tool. This is
a discrete chunk of work; treat it as its own task rather than mixing it into
the layout code.

## 7. Configuration

Implement in phases. Do not attempt phase 3 before phase 1 works on the watch.

**Phase 1:** Hardcode the nine slot assignments in a constant array. Get the
layout, fonts, hands and data reads working and installed on the device. This
is the milestone that matters.

**Phase 2:** Move slot assignments into `Properties`, configurable through the
Garmin Connect phone app. Each of the nine slots becomes a settings enum
choosing from the available field list.

**Phase 3 (optional):** Adopt the Watch Face Configuration API
(`Application.WatchFaceConfig`, API level 5.1.0 and above). Fenix 8 and newer
have a native on-device watch face editor, and this API lets the face plug into
it so slots can be reassigned on the watch itself using Garmin's own UI rather
than through the phone. This is the nicer experience but is newer and more
thinly documented, so it is explicitly last.

## 8. Always-on fallback

Even with always-on disabled in the user's settings, implement a minimal
low-power rendering path so the face does not break if always-on is ever turned
on. In `onEnterSleep`, set a flag; when set, render only the tick marks, the
hands, and at most two data slots. The always-on constraint is a maximum of 10%
of display pixels lit, updated once per minute, so keep this path genuinely
sparse. This is a safety net, not a designed experience.

## 9. Project structure

```
source/
  WatchFaceApp.mc          // AppBase, settings change handling
  WatchFaceView.mc         // WatchFace, onUpdate / onEnterSleep / onExitSleep
  Layout.mc                // resolution-independent geometry, computed at init
  DataProvider.mc          // one function per field, null-safe, returns strings
  SunCalc.mc               // NOAA solar algorithm, daily cache
  Slots.mc                 // slot definition array and field enum
resources/
  drawables/               // monochrome icon bitmaps (text uses built-in vector fonts)
  strings/
  settings/
manifest.xml
monkey.jungle
```

## 10. Acceptance criteria

1. Installs and runs on the physical Fenix 9
2. Renders correctly at 416, 454 and 466 pixel widths in the simulator with no
   hardcoded coordinates
3. Every data field displays a sane placeholder when its source returns null
4. No crash when position has never been acquired (fresh watch, indoors)
5. Sun times recompute at most once per day, verifiable by logging
6. `onUpdate()` contains no `loadResource`, no `Properties.getValue`, no
   `Storage.getValue`, no `has :` checks
7. Hands remain legible where they cross the centre data fields
8. Every tappable slot is verified individually on the physical watch to open
   the correct native glance. Any slot where `exitTo()` does nothing is
   documented and made visually non-tappable rather than left silently dead
9. Three day battery test shows drain within a few percent of the stock face

## 11. Resolved decisions

Decided 2026-09-14:

- **Case size:** base Fenix 9 47mm, device ID `fenix947mm`, 454x454. Primary
  test resolution. 416 (`fenix943mm`) and 466 (`fenix9pro51mm`) are still
  exercised in the simulator for resolution independence
- **Default slots (phase 1 constant array):**

  | Slot | Field |
  |---|---|
  | Ring 1 o'clock | Current weather temperature |
  | Ring 3 o'clock | Next sun event |
  | Ring 5 o'clock | Heart rate |
  | Ring 7 o'clock | Altitude |
  | Ring 9 o'clock | Steps |
  | Ring 11 o'clock | Battery, days left |
  | Centre upper-left | UTC time |
  | Centre upper-right | Pressure, QNH (sea-level), not station pressure. Its icon is a trend arrow (rising / steady / falling) |
  | Centre lower | Date |

- **Accent colours:** tick bars and second hand red; the two upper centre
  icons cyan; a dim colour on the hour hand. Everything else white. Ring order,
  battery in days, the pressure trend arrow and the cyan centre icons all follow
  `reference-concept.jpg`
- **Units:** follow the watch's own settings via `System.getDeviceSettings()`,
  read once at init and on settings change. Altitude uses `elevationUnits`,
  distance uses `distanceUnits`, weather temperature uses `temperatureUnits`. There is no pressure unit setting; pressure is
  always shown in hPa
