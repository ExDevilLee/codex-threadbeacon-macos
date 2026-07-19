#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${THREADBEACON_APP_PATH:-$ROOT/dist/ThreadBeacon.app}"

sounds=(
    Done-Fupicat-Notification
    Done-Bassguitar-Notification
    Done-Beacon
    Done-Chime
    Done-Pulse
    Done-Alert
    Done-Resolve
    Done-Knock
)

for name in "${sounds[@]}"; do
    test -s "$ROOT/Resources/Sounds/$name.wav"
    test -s "$APP/Contents/Resources/Sounds/$name.wav"
    afinfo "$ROOT/Resources/Sounds/$name.wav" | rg -q "44100 Hz"
done

echo "Sound asset verification passed"
