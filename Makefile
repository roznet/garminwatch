# Build and run the watch face with the Connect IQ SDK.
#   make                        build for DEVICE (default fenix947mm)
#   make run                    build, start the simulator if needed, load the face
#   make run DEVICE=fenix943mm  same, for another screen size

SDK_BIN := $(shell cat "$(HOME)/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")bin
KEY ?= $(HOME)/.garmin/developer_key.der
DEVICE ?= fenix947mm
PRG := bin/$(DEVICE).prg
SOURCES := $(wildcard source/*.mc) $(shell find resources -type f) manifest.xml monkey.jungle

.PHONY: build run sim clean

build: $(PRG)

$(PRG): $(SOURCES)
	"$(SDK_BIN)/monkeyc" -f monkey.jungle -d $(DEVICE) -y "$(KEY)" -o $@ -w

sim:
	@pgrep -f ConnectIQ.app/Contents/MacOS/simulator >/dev/null || { "$(SDK_BIN)/connectiq"; sleep 5; }

run: build sim
	"$(SDK_BIN)/monkeydo" $(PRG) $(DEVICE)

clean:
	rm -rf bin
