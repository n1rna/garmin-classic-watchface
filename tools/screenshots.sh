#!/usr/bin/env bash
# Render real simulator screenshots of the face (fixed 10:09 + sample data)
# into screenshots/. Needs the Connect IQ SDK + devices and macOS screen
# recording permission for your terminal.
#
#   tools/screenshots.sh                    # default set
#   tools/screenshots.sh fr265:1 venu3:2    # device:dial (0 black 1 blue 2 aqua 3 silver)
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
DIALS=(black blue aqua silver)
SHOTS=("$@")
[ ${#SHOTS[@]} -eq 0 ] && SHOTS=(fr265:1 fr265:0 fr265:2 fr265:3 venu3:1 fenix7pro:0 epix2pro47mm:2)

mkdir -p bin/demo screenshots
pgrep -f ConnectIQ.app >/dev/null || { "$SDK/bin/connectiq" & sleep 5; }

for shot in "${SHOTS[@]}"; do
    dev="${shot%%:*}"; dial="${shot##*:}"
    out="screenshots/${dev}-${DIALS[$dial]}.png"
    printf 'module DemoConfig {\n    const DIAL = %s;\n}\n' "$dial" > bin/demo/DemoConfig.mc
    "$SDK/bin/monkeyc" -d "$dev" -f "monkey.jungle;demo.jungle" -o bin/demo.prg \
        -y developer_key.der >/dev/null
    pkill -f monkeydo || true
    "$SDK/bin/monkeydo" bin/demo.prg "$dev" >/dev/null 2>&1 &
    sleep 10
    wid="$(swift tools/sim_window_id.swift)"
    screencapture -x -o -l "$wid" bin/demo/raw.png
    swift tools/crop_shot.swift bin/demo/raw.png "$out" >/dev/null
    sips -Z 640 "$out" >/dev/null
    echo "$out"
done
pkill -f monkeydo || true
