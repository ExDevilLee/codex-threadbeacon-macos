#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCES="$ROOT/Resources"
MASTER="$RESOURCES/AppIcon-1024.png"
OUTPUT="$RESOURCES/AppIcon.icns"
TMP_DIR="$(mktemp -d)"
ICONSET="$TMP_DIR/AppIcon.iconset"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$RESOURCES" "$ICONSET"
swift "$ROOT/script/render_app_icon.swift" "$MASTER"

render() {
    local size="$1"
    local filename="$2"
    sips -z "$size" "$size" "$MASTER" --out "$ICONSET/$filename" >/dev/null
}

render 16 icon_16x16.png
render 32 icon_16x16@2x.png
render 32 icon_32x32.png
render 64 icon_32x32@2x.png
render 128 icon_128x128.png
render 256 icon_128x128@2x.png
render 256 icon_256x256.png
render 512 icon_256x256@2x.png
render 512 icon_512x512.png
render 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET" -o "$OUTPUT"
echo "Generated $MASTER"
echo "Generated $OUTPUT"
