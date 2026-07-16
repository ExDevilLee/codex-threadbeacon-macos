#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/CodexThreadStatus.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
PLIST="$CONTENTS/Info.plist"
ICON="$ROOT/Resources/AppIcon.icns"

if [[ ! -s "$ICON" ]]; then
    echo "Missing app icon: $ICON" >&2
    exit 1
fi

pkill -x CodexThreadStatus 2>/dev/null || true
"$ROOT/script/swiftpm.sh" build
BIN_DIR="$("$ROOT/script/swiftpm.sh" build --show-bin-path)"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN_DIR/CodexThreadStatus" "$MACOS/CodexThreadStatus"
cp "$ICON" "$RESOURCES/AppIcon.icns"
chmod +x "$MACOS/CodexThreadStatus"

plutil -create xml1 "$PLIST"
plutil -insert CFBundleExecutable -string CodexThreadStatus "$PLIST"
plutil -insert CFBundleIdentifier -string local.codex-thread-status.poc "$PLIST"
plutil -insert CFBundleName -string CodexThreadStatus "$PLIST"
plutil -insert CFBundleDisplayName -string "Codex 红绿灯" "$PLIST"
plutil -insert CFBundleIconFile -string AppIcon "$PLIST"
plutil -insert CFBundlePackageType -string APPL "$PLIST"
plutil -insert CFBundleShortVersionString -string 0.1.0 "$PLIST"
plutil -insert LSMinimumSystemVersion -string 14.0 "$PLIST"
plutil -insert NSHighResolutionCapable -bool YES "$PLIST"
codesign --force --sign - "$APP" >/dev/null

open -n "$APP"

if [[ "${1:-}" == "--verify" ]]; then
    for _ in {1..20}; do
        if pgrep -x CodexThreadStatus >/dev/null; then
            echo "CodexThreadStatus is running"
            exit 0
        fi
        sleep 0.25
    done
    echo "CodexThreadStatus did not stay running" >&2
    exit 1
fi
