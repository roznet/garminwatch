# Build and run the watch face with the Connect IQ SDK.
#   make                        build for DEVICE (default fenix947mm)
#   make run                    build, start the simulator if needed, load the face
#   make run DEVICE=fenix943mm  same, for another screen size

SDK_BIN := $(shell cat "$(HOME)/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")bin
KEY ?= $(HOME)/.garmin/developer_key.der
DEVICE ?= fenix947mm
PRG := bin/$(DEVICE).prg
SOURCES := $(wildcard source/*.mc) $(shell find resources -type f) manifest.xml monkey.jungle

# Sideloading over USB needs libmtp (brew install libmtp), and nothing else holding the watch:
# quit OpenMTP, Garmin Express and Garmin Aviation Database Manager (its GADM.macos helper can
# outlive the app and keep the connection).
WATCH_DEVICE ?= fenix947mm
APP_FILE := INSTRUMENT
MTP_QUIET := grep -v -E 'extended association|UNKNOWN in libmtp|Please report|^$$'

.PHONY: build run sim clean install logs

build: $(PRG)

$(PRG): $(SOURCES)
	"$(SDK_BIN)/monkeyc" -f monkey.jungle -d $(DEVICE) -y "$(KEY)" -o $@ -w

sim:
	@pgrep -f ConnectIQ.app/Contents/MacOS/simulator >/dev/null || { "$(SDK_BIN)/connectiq"; sleep 5; }

run: build sim
	"$(SDK_BIN)/monkeydo" $(PRG) $(DEVICE)

# Build for the physical watch and copy it to GARMIN/Apps, replacing any previous copy.
# Also resets GARMIN/Apps/LOGS/INSTRUMENT.TXT, which makes the watch keep System.println output.
install:
	$(MAKE) build DEVICE=$(WATCH_DEVICE)
	cp bin/$(WATCH_DEVICE).prg bin/$(APP_FILE).PRG
	: > bin/$(APP_FILE).TXT
	-@mtp-connect --delete /GARMIN/Apps/$(APP_FILE).PRG 2>&1 | $(MTP_QUIET) >/dev/null
	-@mtp-connect --delete /GARMIN/Apps/LOGS/$(APP_FILE).TXT 2>&1 | $(MTP_QUIET) >/dev/null
	@out=$$(mtp-sendfile bin/$(APP_FILE).PRG /GARMIN/Apps 2>&1); echo "$$out" | $(MTP_QUIET); echo "$$out" | grep -q 'New file ID'
	@out=$$(mtp-sendfile bin/$(APP_FILE).TXT /GARMIN/Apps/LOGS 2>&1); echo "$$out" | $(MTP_QUIET); echo "$$out" | grep -q 'New file ID'
	@echo "Installed. Unplug the watch and pick the Instrument face."

# Copy the app's println log and the Connect IQ crash log from the watch into bin/
logs:
	-@mtp-getfile /GARMIN/Apps/LOGS/$(APP_FILE).TXT bin/watch-$(APP_FILE).TXT 2>&1 | $(MTP_QUIET)
	-@mtp-getfile /GARMIN/Apps/LOGS/CIQ_LOG.YML bin/watch-CIQ_LOG.YML 2>&1 | $(MTP_QUIET)

clean:
	rm -rf bin
