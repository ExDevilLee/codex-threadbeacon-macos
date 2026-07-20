#!/usr/bin/env bash

validate_release_tag() {
    local tag="$1"
    [[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || {
        echo "Invalid release tag: $tag (expected vMAJOR.MINOR.PATCH)" >&2
        return 1
    }
}

version_from_tag() {
    local tag="$1"
    validate_release_tag "$tag"
    printf '%s\n' "${tag#v}"
}

require_changelog_version() {
    local changelog="$1"
    local version="$2"
    local escaped_version="${version//./\.}"

    rg -q "^## \\[$escaped_version\\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$changelog" || {
        echo "CHANGELOG is missing version $version" >&2
        return 1
    }
}

extract_changelog_version() {
    local changelog="$1"
    local version="$2"

    require_changelog_version "$changelog" "$version"
    awk -v target="## [$version] - " '
        index($0, target) == 1 { printing = 1 }
        printing && $0 ~ /^## \[/ && index($0, target) != 1 { exit }
        printing { print }
    ' "$changelog"
}
