#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/ThreadBeacon.app"
PROJECT="$ROOT/ThreadBeacon.xcodeproj"
DERIVED_DATA="$ROOT/.build/xcode-script"
CONFIGURATION="${THREADBEACON_CONFIGURATION:-Debug}"
BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/ThreadBeacon.app"
TEAM_ID="${THREADBEACON_DEVELOPMENT_TEAM:-}"

if [[ ! -d "$PROJECT" ]]; then
    echo "Missing Xcode project: $PROJECT" >&2
    exit 1
fi

pkill -x ThreadBeacon 2>/dev/null || true

XCODEBUILD_ARGS=(
    -project "$PROJECT"
    -scheme ThreadBeacon
    -configuration "$CONFIGURATION"
    -destination platform=macOS
    -derivedDataPath "$DERIVED_DATA"
)

if [[ -n "$TEAM_ID" ]]; then
    XCODEBUILD_ARGS+=(
        DEVELOPMENT_TEAM="$TEAM_ID"
        CODE_SIGN_STYLE=Automatic
        "CODE_SIGN_IDENTITY=Apple Development"
        -allowProvisioningUpdates
    )
else
    XCODEBUILD_ARGS+=(
        CODE_SIGN_STYLE=Manual
        CODE_SIGN_IDENTITY=-
    )
fi

xcodebuild "${XCODEBUILD_ARGS[@]}" build

test -d "$BUILT_APP"
rm -rf "$APP"
ditto "$BUILT_APP" "$APP"
codesign --verify --deep --strict "$APP"

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
