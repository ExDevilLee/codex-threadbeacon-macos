#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/ThreadBeacon.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
PLIST="$CONTENTS/Info.plist"
ICON="$ROOT/Resources/AppIcon.icns"
SOUNDS="$ROOT/Resources/Sounds"

if [[ ! -s "$ICON" ]]; then
    echo "Missing app icon: $ICON" >&2
    exit 1
fi
if [[ ! -d "$SOUNDS" ]]; then
    echo "Missing sound assets: $SOUNDS" >&2
    exit 1
fi

pkill -x ThreadBeacon 2>/dev/null || true
"$ROOT/script/swiftpm.sh" build
BIN_DIR="$("$ROOT/script/swiftpm.sh" build --show-bin-path)"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN_DIR/ThreadBeacon" "$MACOS/ThreadBeacon"
cp "$ICON" "$RESOURCES/AppIcon.icns"
mkdir -p "$RESOURCES/Sounds"
cp "$SOUNDS"/*.wav "$RESOURCES/Sounds/"
chmod +x "$MACOS/ThreadBeacon"

plutil -create xml1 "$PLIST"
plutil -insert CFBundleExecutable -string ThreadBeacon "$PLIST"
plutil -insert CFBundleIdentifier -string io.github.exdevillee.threadbeacon.macos "$PLIST"
plutil -insert CFBundleName -string ThreadBeacon "$PLIST"
plutil -insert CFBundleDisplayName -string ThreadBeacon "$PLIST"
plutil -insert CFBundleIconFile -string AppIcon "$PLIST"
plutil -insert CFBundlePackageType -string APPL "$PLIST"
plutil -insert CFBundleShortVersionString -string 0.1.0 "$PLIST"
plutil -insert LSMinimumSystemVersion -string 14.0 "$PLIST"
plutil -insert NSHighResolutionCapable -bool YES "$PLIST"
codesign --force --sign - "$APP" >/dev/null

open -n "$APP"

if [[ "${1:-}" == "--verify" ]]; then
    for _ in {1..20}; do
        if pgrep -x ThreadBeacon >/dev/null; then
            echo "ThreadBeacon is running"
            exit 0
        fi
        sleep 0.25
    done
    echo "ThreadBeacon did not stay running" >&2
    exit 1
fi
