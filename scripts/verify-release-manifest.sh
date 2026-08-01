#!/usr/bin/env bash
set -euo pipefail

[[ "$#" -eq 6 ]] || {
    echo "Usage: $0 MANIFEST BUILD_NUMBER_FILE MAC_ZIP RC_TAG COMMIT_SHA VERSION" >&2
    exit 2
}

manifest="$1"
build_number_file="$2"
mac_zip="$3"
rc_tag="$4"
commit_sha="$5"
version="$6"

[[ -f "$manifest" ]] || { echo "Missing manifest: $manifest" >&2; exit 1; }
[[ -f "$build_number_file" ]] || { echo "Missing build number: $build_number_file" >&2; exit 1; }
[[ -f "$mac_zip" ]] || { echo "Missing Mac zip: $mac_zip" >&2; exit 1; }

build_number=$(tr -d '\n' < "$build_number_file")
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] || {
    echo "Invalid build number: $build_number" >&2
    exit 1
}

filename=$(basename "$mac_zip")
jq -e \
    --arg tag "$rc_tag" \
    --arg commit "$commit_sha" \
    --arg version "$version" \
    --arg build_number "$build_number" \
    --arg filename "$filename" \
    '.schema_version == 1 and .tag == $tag and .commit == $commit and .marketing_version == $version and .build_number == $build_number and .mac_filename == $filename and (.mac_sha256 | test("^[0-9a-f]{64}$"))' \
    "$manifest" >/dev/null

expected_sha=$(jq -r .mac_sha256 "$manifest")
actual_sha=$(shasum -a 256 "$mac_zip" | cut -d' ' -f1)
[[ "$expected_sha" == "$actual_sha" ]] || {
    echo "Mac zip digest mismatch: expected $expected_sha, got $actual_sha" >&2
    exit 1
}

printf '%s\n' "$actual_sha"
