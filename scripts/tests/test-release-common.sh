#!/usr/bin/env bash
# Unit tests for scripts/lib/release-common.sh.
# Run via: just test-release-scripts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/release-common.sh"

PASS=0
FAIL=0

assert_eq() {
    local expected="$1" actual="$2" name="$3"
    if [[ "$expected" == "$actual" ]]; then
        printf '  PASS: %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf '  FAIL: %s\n' "$name"
        printf '    expected: %s\n' "$expected"
        printf '    actual:   %s\n' "$actual"
        FAIL=$((FAIL + 1))
    fi
}

echo "== compute_next_rc_version =="

# Case 1: no tags at all (first release ever).
result=$(compute_next_rc_version "1.0.0" "")
assert_eq \
    '{"version":"1.0.0-rc.1","confirm_marketing":false,"notes_base":""}' \
    "$result" \
    "first rc, no prior tags"

# Case 2: rc.1 already exists, bump to rc.2.
tags=$'v1.0.0-rc.1'
result=$(compute_next_rc_version "1.0.0" "$tags")
assert_eq \
    '{"version":"1.0.0-rc.2","confirm_marketing":false,"notes_base":"v1.0.0-rc.1"}' \
    "$result" \
    "second rc"

# Case 3: rc.10 ordering (lexicographic vs numeric).
tags=$'v1.0.0-rc.1\nv1.0.0-rc.2\nv1.0.0-rc.9\nv1.0.0-rc.10'
result=$(compute_next_rc_version "1.0.0" "$tags")
assert_eq \
    '{"version":"1.0.0-rc.11","confirm_marketing":false,"notes_base":"v1.0.0-rc.10"}' \
    "$result" \
    "rc.10 sorts numerically"

# Case 4: previous final exists, no RC for new marketing version.
tags=$'v0.9.0-rc.1\nv0.9.0\nv1.0.0-rc.1\nv1.0.0'
result=$(compute_next_rc_version "1.1.0" "$tags")
assert_eq \
    '{"version":"1.1.0-rc.1","confirm_marketing":true,"notes_base":"v1.0.0"}' \
    "$result" \
    "rc.1 after final, confirm_marketing=true"

# Case 5: prior RCs from older marketing versions don't bleed in.
tags=$'v0.9.0-rc.1\nv0.9.0\nv1.0.0-rc.1\nv1.0.0\nv1.1.0-rc.3'
result=$(compute_next_rc_version "1.1.0" "$tags")
assert_eq \
    '{"version":"1.1.0-rc.4","confirm_marketing":false,"notes_base":"v1.1.0-rc.3"}' \
    "$result" \
    "rc.N+1 ignores other marketing versions"

echo
echo "== compute_final_version =="

# Case 6: final after rc.3.
tags=$'v1.1.0-rc.1\nv1.1.0-rc.2\nv1.1.0-rc.3\nv1.0.0'
result=$(compute_final_version "1.1.0" "$tags" "abc1234")
assert_eq \
    '{"version":"1.1.0","rc_tag":"v1.1.0-rc.3","commit":"abc1234","notes_base":"v1.0.0"}' \
    "$result" \
    "final picks latest RC and prev final"

# Case 7: final but no RC exists — must error.
if compute_final_version "1.1.0" "" "abc1234" 2>/dev/null; then
    echo "  FAIL: final with no RC should have errored"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: final with no RC errors"
    PASS=$((PASS + 1))
fi

# Case 8: final with no prior final.
tags=$'v1.0.0-rc.1'
result=$(compute_final_version "1.0.0" "$tags" "abc1234")
assert_eq \
    '{"version":"1.0.0","rc_tag":"v1.0.0-rc.1","commit":"abc1234","notes_base":""}' \
    "$result" \
    "final with no prior final"

echo
echo "== validate_final_pair =="

if validate_final_pair "1.0.0" "v1.0.0-rc.2" "v1.0.0-rc.2" "abc" "abc"; then
    echo "  PASS: matching latest RC pair"
    PASS=$((PASS + 1))
else
    echo "  FAIL: matching latest RC pair"
    FAIL=$((FAIL + 1))
fi

if validate_final_pair "1.0.0" "v1.0.0-rc.1" "v1.0.0-rc.2" "abc" "abc" 2>/dev/null; then
    echo "  FAIL: older RC should fail"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: older RC fails"
    PASS=$((PASS + 1))
fi

if validate_final_pair "1.0.0" "v1.0.0-rc.2" "v1.0.0-rc.2" "abc" "def" 2>/dev/null; then
    echo "  FAIL: differing commits should fail"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: differing commits fail"
    PASS=$((PASS + 1))
fi

echo
echo "== verify-release-manifest =="

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
printf 'mac archive' > "$tmp_dir/Bruce-1.0.0.zip"
printf '42\n' > "$tmp_dir/build-number.txt"
mac_sha=$(shasum -a 256 "$tmp_dir/Bruce-1.0.0.zip" | cut -d' ' -f1)
jq -n \
    --arg tag "v1.0.0-rc.1" \
    --arg commit "abc1234" \
    --arg version "1.0.0" \
    --arg build_number "42" \
    --arg mac_filename "Bruce-1.0.0.zip" \
    --arg mac_sha256 "$mac_sha" \
    '{schema_version: 1, tag: $tag, commit: $commit, marketing_version: $version, build_number: $build_number, mac_filename: $mac_filename, mac_sha256: $mac_sha256}' \
    > "$tmp_dir/release-manifest.json"

if "$SCRIPT_DIR/../verify-release-manifest.sh" \
    "$tmp_dir/release-manifest.json" \
    "$tmp_dir/build-number.txt" \
    "$tmp_dir/Bruce-1.0.0.zip" \
    "v1.0.0-rc.1" \
    "abc1234" \
    "1.0.0" >/dev/null; then
    echo "  PASS: valid release manifest"
    PASS=$((PASS + 1))
else
    echo "  FAIL: valid release manifest"
    FAIL=$((FAIL + 1))
fi

printf 'tampered archive' > "$tmp_dir/Bruce-1.0.0.zip"
if "$SCRIPT_DIR/../verify-release-manifest.sh" \
    "$tmp_dir/release-manifest.json" \
    "$tmp_dir/build-number.txt" \
    "$tmp_dir/Bruce-1.0.0.zip" \
    "v1.0.0-rc.1" \
    "abc1234" \
    "1.0.0" >/dev/null 2>&1; then
    echo "  FAIL: tampered Mac zip should fail"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: tampered Mac zip fails"
    PASS=$((PASS + 1))
fi

echo
echo "== check-release-build-number =="

if CONFIGURATION=Debug CURRENT_PROJECT_VERSION=1 \
    "$SCRIPT_DIR/../check-release-build-number.sh"; then
    echo "  PASS: Debug placeholder is allowed"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Debug placeholder should be allowed"
    FAIL=$((FAIL + 1))
fi

if CONFIGURATION=Release CURRENT_PROJECT_VERSION=1 \
    "$SCRIPT_DIR/../check-release-build-number.sh" >/dev/null 2>&1; then
    echo "  FAIL: Release placeholder should fail"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: Release placeholder fails"
    PASS=$((PASS + 1))
fi

if CONFIGURATION=Release CURRENT_PROJECT_VERSION=42 \
    "$SCRIPT_DIR/../check-release-build-number.sh"; then
    echo "  PASS: incremented Release build is allowed"
    PASS=$((PASS + 1))
else
    echo "  FAIL: incremented Release build should be allowed"
    FAIL=$((FAIL + 1))
fi

echo
echo "Total: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
