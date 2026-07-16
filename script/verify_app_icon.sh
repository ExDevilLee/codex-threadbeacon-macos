#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/CodexThreadStatus.app"
PLIST="$APP/Contents/Info.plist"

test -s "$ROOT/Resources/AppIcon-1024.png"
test -s "$ROOT/Resources/AppIcon.icns"
test -s "$APP/Contents/Resources/AppIcon.icns"
test "$(plutil -extract CFBundleIconFile raw "$PLIST")" = "AppIcon"

echo "App icon bundle verification passed"
