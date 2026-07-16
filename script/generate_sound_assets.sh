#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$ROOT/Resources/Sounds"

mkdir -p "$OUTPUT"
swift "$ROOT/script/render_sound_assets.swift" "$OUTPUT"
echo "Generated ThreadBeacon sound assets"
