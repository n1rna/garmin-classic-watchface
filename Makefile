# Usage:  make run                 (build + open in simulator, Forerunner 265)
#         make run DEVICE=fenix7   (pick another watch)
#         make install            (build + copy to the watch over USB)
#         make build / make clean
DEVICE ?= fr265
SDK    ?= $(shell cat "$(HOME)/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg" 2>/dev/null)
KEY    ?= developer_key.der
OUT    := bin/Classic.prg

build:
	@test -n "$(SDK)" || (echo "Connect IQ SDK not found - install it with the SDK Manager first." && exit 1)
	@mkdir -p bin
	"$(SDK)/bin/monkeyc" -d $(DEVICE) -f monkey.jungle -o $(OUT) -y $(KEY) -w

sim:
	@pgrep -f ConnectIQ.app >/dev/null || ("$(SDK)/bin/connectiq" & sleep 4)

run: build sim
	"$(SDK)/bin/monkeydo" $(OUT) $(DEVICE)

install: build
	python3 tools/install_to_watch.py $(OUT)

clean:
	rm -rf bin

.PHONY: build sim run install clean
