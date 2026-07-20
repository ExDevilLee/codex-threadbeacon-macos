#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/script/release_lib.sh"

APP="${1:?Usage: verify_release.sh APP_PATH TAG}"
TAG="${2:?Usage: verify_release.sh APP_PATH TAG}"
VERSION="$(version_from_tag "$TAG")"
PLIST="$APP/Contents/Info.plist"
EXECUTABLE="$APP/Contents/MacOS/ThreadBeacon"

fail() {
    echo "$1" >&2
    exit 1
}

"$ROOT/script/verify_app_identity.sh" "$APP"

ACTUAL_VERSION="$(plutil -extract CFBundleShortVersionString raw "$PLIST")"
BUILD_NUMBER="$(plutil -extract CFBundleVersion raw "$PLIST")"
[[ "$ACTUAL_VERSION" == "$VERSION" ]] || \
    fail "App version $ACTUAL_VERSION does not match tag $TAG"
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || \
    fail "Invalid App build number: $BUILD_NUMBER"

ARCHS="$(lipo -archs "$EXECUTABLE")"
for required_arch in arm64 x86_64; do
    [[ " $ARCHS " == *" $required_arch "* ]] || \
        fail "Release executable is missing architecture: $required_arch"
done

codesign --verify --deep --strict "$APP"
SIGNATURE_INFO="$(codesign -dv --verbose=4 "$APP" 2>&1)"
grep -Eq '^Signature=adhoc$' <<< "$SIGNATURE_INFO" || \
    fail "Release App is not ad-hoc signed"

echo "Release verification passed: $VERSION ($BUILD_NUMBER), $ARCHS"
