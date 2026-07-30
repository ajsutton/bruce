#!/usr/bin/env bash
set -euo pipefail

export SWIFTPM_DISABLE_SANDBOX=1
export SWIFT_BUILD_USE_SANDBOX=0

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILTERS=("$@")
SIMULATOR="$(bash "$REPO_ROOT/scripts/find-simulator.sh")"
mkdir -p "$REPO_ROOT/.agent-tmp"
RESULT_DIRECTORY="$(mktemp -d "$REPO_ROOT/.agent-tmp/ui-test.XXXXXX")"
RESULT_BUNDLE="$RESULT_DIRECTORY/BruceUITests.xcresult"
FILTER_FLAGS=()

for filter in ${FILTERS[@]+"${FILTERS[@]}"}; do
  if [[ "$filter" == BruceUITests_iOS/* ]]; then
    FILTER_FLAGS+=("-only-testing:$filter")
  else
    FILTER_FLAGS+=("-only-testing:BruceUITests_iOS/$filter")
  fi
done

echo "UI test result bundle: $RESULT_BUNDLE"
xcodebuild test \
  -IDEPackageSupportDisableManifestSandbox=1 \
  -IDEPackageSupportDisablePackageSandbox=1 \
  -derivedDataPath "$REPO_ROOT/.agent-tmp/DerivedData-ios-ui" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -scheme Bruce-UI-Tests \
  -destination "platform=iOS Simulator,id=$SIMULATOR" \
  "OTHER_SWIFT_FLAGS=\$(inherited) -disable-sandbox" \
  CODE_SIGNING_ALLOWED=NO \
  ${FILTER_FLAGS[@]+"${FILTER_FLAGS[@]}"}
