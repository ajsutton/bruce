#!/usr/bin/env bash
set -euo pipefail

export SWIFTPM_DISABLE_SANDBOX=1
export SWIFT_BUILD_USE_SANDBOX=0

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM="${1:-all}"
shift || true
FILTERS=("$@")

COMMON_ARGS=(
  -IDEPackageSupportDisableManifestSandbox=1
  -IDEPackageSupportDisablePackageSandbox=1
  # xcodebuild must receive the literal inherited-setting expression.
  "OTHER_SWIFT_FLAGS=\$(inherited) -disable-sandbox"
)

print_filter_flags() {
  local target="$1"
  local filter
  for filter in ${FILTERS[@]+"${FILTERS[@]}"}; do
    if [[ "$filter" == SmartHomeTests_* ]]; then
      printf -- '-only-testing:%s\n' "$filter"
    else
      printf -- '-only-testing:%s/%s\n' "$target" "$filter"
    fi
  done
}

run_ios() {
  local simulator
  local filter_flags=()
  simulator="$(bash "$REPO_ROOT/scripts/find-simulator.sh")"
  while IFS= read -r line; do
    filter_flags+=("$line")
  done < <(print_filter_flags "SmartHomeTests_iOS")

  xcodebuild test "${COMMON_ARGS[@]}" \
    -derivedDataPath "$REPO_ROOT/.DerivedData-ios" \
    -scheme SmartHome-iOS \
    -destination "platform=iOS Simulator,id=$simulator" \
    CODE_SIGNING_ALLOWED=NO \
    ${filter_flags[@]+"${filter_flags[@]}"}
}

run_mac() {
  local filter_flags=()
  while IFS= read -r line; do
    filter_flags+=("$line")
  done < <(print_filter_flags "SmartHomeTests_macOS")

  xcodebuild test "${COMMON_ARGS[@]}" \
    -derivedDataPath "$REPO_ROOT/.DerivedData-mac" \
    -scheme SmartHome-macOS \
    -destination "platform=macOS" \
    CODE_SIGNING_ALLOWED=NO \
    ${filter_flags[@]+"${filter_flags[@]}"}
}

case "$PLATFORM" in
  ios)
    run_ios
    ;;
  mac)
    run_mac
    ;;
  all)
    ios_log="$(mktemp)"
    mac_log="$(mktemp)"
    trap 'rm -f "$ios_log" "$mac_log"' EXIT

    run_ios >"$ios_log" 2>&1 &
    ios_pid=$!
    run_mac >"$mac_log" 2>&1 &
    mac_pid=$!

    failed=0
    wait "$ios_pid" || failed=1
    wait "$mac_pid" || failed=1

    echo "================= iOS Simulator output ================="
    sed -n '1,2000p' "$ios_log"
    echo "==================== macOS output ======================"
    sed -n '1,2000p' "$mac_log"

    if [[ "$failed" -ne 0 ]]; then
      exit 1
    fi
    ;;
  *)
    echo "Usage: $0 [all|ios|mac] [FILTER ...]" >&2
    exit 1
    ;;
esac

echo "All tests passed."
