# Instrument

A deliberately plain analog watch face for the Garmin Fenix 9, built for the
way I want to read a watch: thin hands, a black dial, and nine small data
slots that look like an instrument panel rather than a consumer smartwatch.

This is a personal project, not a product. It is published in case it is
useful to someone else: take it, change it, publish your own version, no need
to ask. See [LICENSE](LICENSE) (MIT). Not affiliated with or endorsed by
Garmin.

## What it shows

Six slots around the ring, clockwise from 1 o'clock: weather temperature, next
sun event, heart rate, altitude, steps, battery days. In the centre: UTC time,
sea-level pressure (QNH) with a trend arrow, and the date.

Press and hold a slot to open the watch's own glance for that field. UTC has
no glance behind it, since the watch publishes no time zone complication.

Everything is read from the watch: no web requests, no background process, no
GPS wake-ups. All geometry is computed from the screen size at runtime, so it
renders correctly on the 416, 454 and 466 px Fenix 9 variants.

The design is written up in
[designs/fenix9-watchface-spec.md](designs/fenix9-watchface-spec.md), which
covers the layout, data sources, battery rules and what was verified on a real
watch.

## Building

You need:

- [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) 9.2 or later,
  with the Fenix 9 device files installed via the SDK Manager
- A Java runtime (the compiler is Java; Temurin 21 works)
- A developer key, which is just a key you generate yourself:

```sh
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem \
    -out developer_key.der -nocrypt
```

Then:

```sh
make                          # build for the 47 mm Fenix 9 (fenix947mm)
make run                      # build, start the simulator, load the face
make run DEVICE=fenix943mm    # or fenix9pro51mm, etc.
```

The Makefile expects the key at `~/.garmin/developer_key.der`; override with
`make KEY=/path/to/key.der`.

## Installing on a watch

Sideloading needs no Garmin account. On macOS with
[libmtp](https://formulae.brew.sh/formula/libmtp) installed:

```sh
make install    # build, then copy to GARMIN/Apps over USB
make logs       # copy the app log and crash log back into bin/
```

Or copy `bin/<device>.prg` into `GARMIN/Apps` on the watch yourself with any
MTP file manager.

Two things that cost me time:

- **Restart the watch after installing.** It keeps the running face in memory,
  and re-selecting the face is not enough to load a new build.
- **The watch leaves transfer mode** if it sits on the cable a while. It stays
  plugged in but stops offering MTP; unplug and replug to get it back.

## Layout of the code

```
source/
  WatchFaceApp.mc       AppBase, returns the view and the press delegate
  WatchFaceView.mc      drawing: ticks, ring slots, centre block, hands
  InstrumentDelegate.mc press and hold to open a glance
  Layout.mc             all geometry, computed once from the screen size
  DataProvider.mc       one null-safe function per field, returns strings
  SunCalc.mc            sunrise/sunset fallback when the watch has no value
  Slots.mc              which field is in which slot, and its complication
resources/
  drawables/icons/      monochrome SVG icons, scaled to the screen
```

Colours, sizes and slot assignments are constants at the top of
`WatchFaceView.mc`, `Layout.mc` and `Slots.mc`.

## Status

Runs on a physical Fenix 9 47 mm. Slot assignments are fixed in code; making
them configurable from the Garmin Connect phone app is the next step, and
supporting the watch's own face editor is a possible one after that.
