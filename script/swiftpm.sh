#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="/Library/Developer/CommandLineTools/usr/lib/swift/pm/ManifestAPI"
CUSTOM_LIBS="$ROOT/.build/swiftpm-libs"

if [[ -f "$SOURCE/PackageDescription.swiftmodule/arm64-apple-macos.private.swiftinterface" ]]; then
    mkdir -p "$CUSTOM_LIBS/ManifestAPI"
    rsync -a --delete --exclude='*.private.swiftinterface' "$SOURCE/" "$CUSTOM_LIBS/ManifestAPI/"
    export SWIFTPM_CUSTOM_LIBS_DIR="$CUSTOM_LIBS"
    export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/swiftpm-module-cache"
fi

export DYLD_FRAMEWORK_PATH="/Library/Developer/CommandLineTools/Library/Developer/Frameworks${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}"
export DYLD_LIBRARY_PATH="/Library/Developer/CommandLineTools/Library/Developer/usr/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"

cd "$ROOT"
exec swift "$@"
