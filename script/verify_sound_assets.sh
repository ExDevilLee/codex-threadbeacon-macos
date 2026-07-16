#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

for name in Done-Beacon Done-Chime Done-Pulse; do
    test -s "$ROOT/Resources/Sounds/$name.wav"
    test -s "$ROOT/dist/ThreadBeacon.app/Contents/Resources/Sounds/$name.wav"
    afinfo "$ROOT/Resources/Sounds/$name.wav" | rg -q "44100 Hz"
done

echo "Sound asset verification passed"
