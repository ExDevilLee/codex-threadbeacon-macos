#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/script/release_lib.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

## [0.1.0] - 2026-07-20

### Added

- First preview.

## [0.0.1] - 2026-07-19
EOF

assert_eq() {
    [[ "$1" == "$2" ]] || {
        echo "Expected '$2', got '$1'" >&2
        exit 1
    }
}

validate_release_tag "v0.1.0"
if validate_release_tag "0.1.0" 2>/dev/null; then
    echo "Expected an invalid tag failure" >&2
    exit 1
fi
if invalid_version="$(version_from_tag "0.1.0" 2>/dev/null)"; then
    echo "Expected invalid tag conversion to fail, got $invalid_version" >&2
    exit 1
fi
assert_eq "$(version_from_tag "v0.1.0")" "0.1.0"
require_changelog_version "$TMP/CHANGELOG.md" "0.1.0"
if require_changelog_version "$TMP/CHANGELOG.md" "0.2.0" 2>/dev/null; then
    echo "Expected a missing changelog version failure" >&2
    exit 1
fi
extract_changelog_version "$TMP/CHANGELOG.md" "0.1.0" > "$TMP/notes.md"
grep -Eq '^## \[0\.1\.0\]' "$TMP/notes.md"
grep -Eq 'First preview\.' "$TMP/notes.md"
if grep -Eq '0\.0\.1' "$TMP/notes.md"; then
    echo "Release notes included the next version" >&2
    exit 1
fi

echo "Release metadata tests passed"
