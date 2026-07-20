#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/script/release_lib.sh"

TAG="${1:?Usage: package_release.sh vMAJOR.MINOR.PATCH}"
VERSION="$(version_from_tag "$TAG")"
PROJECT="$ROOT/ThreadBeacon.xcodeproj"
DERIVED_DATA="$ROOT/.build/xcode-release"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/ThreadBeacon.app"
OUTPUT_DIR="$ROOT/dist/release"
ARCHIVE_NAME="ThreadBeacon-$TAG-macos-universal.zip"
ARCHIVE="$OUTPUT_DIR/$ARCHIVE_NAME"
CHECKSUM="$ARCHIVE.sha256"
RELEASE_NOTES="$OUTPUT_DIR/release-notes.md"

fail() {
    echo "$1" >&2
    exit 1
}

read_build_setting() {
    local configuration="$1"
    local key="$2"

    xcodebuild \
        -project "$PROJECT" \
        -target ThreadBeacon \
        -configuration "$configuration" \
        -showBuildSettings 2>/dev/null |
        sed -n "s/^[[:space:]]*$key = //p" |
        head -n 1
}

test -d "$PROJECT" || fail "Missing Xcode project: $PROJECT"
require_changelog_version "$ROOT/CHANGELOG.md" "$VERSION"

DEBUG_VERSION="$(read_build_setting Debug MARKETING_VERSION)"
RELEASE_VERSION="$(read_build_setting Release MARKETING_VERSION)"
DEBUG_BUILD="$(read_build_setting Debug CURRENT_PROJECT_VERSION)"
RELEASE_BUILD="$(read_build_setting Release CURRENT_PROJECT_VERSION)"

[[ "$DEBUG_VERSION" == "$RELEASE_VERSION" ]] || \
    fail "Debug and Release marketing versions differ"
[[ "$DEBUG_BUILD" == "$RELEASE_BUILD" ]] || \
    fail "Debug and Release build numbers differ"
[[ "$RELEASE_VERSION" == "$VERSION" ]] || \
    fail "Project version $RELEASE_VERSION does not match tag $TAG"
[[ "$RELEASE_BUILD" =~ ^[1-9][0-9]*$ ]] || \
    fail "Invalid project build number: $RELEASE_BUILD"

rm -rf "$DERIVED_DATA"
mkdir -p "$OUTPUT_DIR"
rm -f "$ARCHIVE" "$CHECKSUM" "$RELEASE_NOTES"

xcodebuild \
    -project "$PROJECT" \
    -scheme ThreadBeacon \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    build

test -d "$BUILT_APP" || fail "Release build did not produce $BUILT_APP"
"$ROOT/script/verify_release.sh" "$BUILT_APP" "$TAG"

ditto -c -k --sequesterRsrc --keepParent "$BUILT_APP" "$ARCHIVE"
test -s "$ARCHIVE" || fail "Release archive is empty: $ARCHIVE"
(
    cd "$OUTPUT_DIR"
    shasum -a 256 "$ARCHIVE_NAME" > "$(basename "$CHECKSUM")"
    shasum -a 256 -c "$(basename "$CHECKSUM")"
)
extract_changelog_version "$ROOT/CHANGELOG.md" "$VERSION" > "$RELEASE_NOTES"
test -s "$RELEASE_NOTES" || fail "Release notes are empty"

UNPACK_DIR="$(mktemp -d)"
trap 'rm -rf "$UNPACK_DIR"' EXIT
ditto -x -k "$ARCHIVE" "$UNPACK_DIR"
"$ROOT/script/verify_release.sh" "$UNPACK_DIR/ThreadBeacon.app" "$TAG"

echo "Release package ready: $ARCHIVE"
echo "Checksum ready: $CHECKSUM"
