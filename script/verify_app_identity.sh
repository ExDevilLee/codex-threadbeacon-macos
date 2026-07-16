#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/ThreadBeacon.app"
PLIST="$APP/Contents/Info.plist"

test -d "$APP"
test -x "$APP/Contents/MacOS/ThreadBeacon"
test "$(plutil -extract CFBundleExecutable raw "$PLIST")" = "ThreadBeacon"
test "$(plutil -extract CFBundleIdentifier raw "$PLIST")" = \
    "io.github.exdevillee.threadbeacon.macos"
test "$(plutil -extract CFBundleName raw "$PLIST")" = "ThreadBeacon"
test "$(plutil -extract CFBundleDisplayName raw "$PLIST")" = "ThreadBeacon"

echo "App identity verification passed"
