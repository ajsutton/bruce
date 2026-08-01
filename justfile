# Bruce native app — common development tasks.
set dotenv-load

default:
    @just --list

generate:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .build
    xcodegen generate --use-cache --cache-path .build/xcodegen.cache

format:
    #!/usr/bin/env bash
    set -euo pipefail
    find App Tests UITestHost UITests -type f -name '*.swift' -print0 \
        | xargs -0 swift-format format -i --configuration .swift-format
    swiftlint lint --fix --quiet

format-check:
    #!/usr/bin/env bash
    set -euo pipefail
    fail=0
    while IFS= read -r -d '' file; do
        if ! cmp -s "$file" <(swift-format format --configuration .swift-format "$file"); then
            echo "::error file=$file::Not formatted; run 'just format' to fix"
            diff -u --label "$file" --label "$file (formatted)" \
                "$file" <(swift-format format --configuration .swift-format "$file") || true
            fail=1
        fi
    done < <(find App Tests UITestHost UITests -type f -name '*.swift' -print0)
    if [ "$fail" -ne 0 ]; then
        exit 1
    fi
    echo "All Swift files are correctly formatted."
    swiftlint lint --strict --quiet

check-site:
    bash scripts/check-pages-site.sh

build: build-mac build-ios

build-mac: generate
    xcodebuild build \
        -scheme Bruce-macOS \
        -destination 'platform=macOS' \
        -derivedDataPath .build \
        CODE_SIGNING_ALLOWED=NO

build-mac-for-running: generate
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
        echo "DEVELOPMENT_TEAM must be set in .env for a signed runtime build." >&2
        exit 1
    fi
    xcodebuild build \
        -allowProvisioningUpdates \
        -scheme Bruce-macOS \
        -destination 'platform=macOS' \
        -derivedDataPath .build \
        DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
        CODE_SIGNING_ALLOWED=YES

# Build and launch the macOS app; extra arguments are forwarded to the app.
[positional-arguments]
run-mac *args: build-mac-for-running
    #!/usr/bin/env bash
    set -euo pipefail
    app_path=".build/Build/Products/Debug/Bruce.app"
    app_binary="$app_path/Contents/MacOS/Bruce"
    if [ "$#" -gt 0 ]; then
        pkill -f "Bruce.app/Contents/MacOS/Bruce" 2>/dev/null || true
        nohup "$app_binary" "$@" >/dev/null 2>&1 &
        disown
    else
        open "$app_path"
    fi

# Launch the macOS app and capture this process's unified logs.
[positional-arguments]
run-mac-with-logs predicate='subsystem == "net.symphonious.bruce"' *args: generate
    bash scripts/run-with-logs.sh "$@"

build-ios: generate
    #!/usr/bin/env bash
    set -euo pipefail
    simulator="$(bash scripts/find-simulator.sh)"
    xcodebuild build \
        -scheme Bruce-iOS \
        -destination "platform=iOS Simulator,id=$simulator" \
        -derivedDataPath .build-ios \
        CODE_SIGNING_ALLOWED=NO

test *FILTERS: generate
    bash scripts/test.sh all {{ FILTERS }}

test-mac *FILTERS: generate
    bash scripts/test.sh mac {{ FILTERS }}

test-ios *FILTERS: generate
    bash scripts/test.sh ios {{ FILTERS }}

test-ui *FILTERS: generate
    bash scripts/test-ui.sh {{ FILTERS }}

test-release-scripts:
    bash scripts/tests/test-release-common.sh

validate-ios: generate
    bundle exec fastlane ios validate

testflight: generate
    bundle exec fastlane ios beta

bump-version version:
    sed -i '' 's/MARKETING_VERSION: .*/MARKETING_VERSION: "{{ version }}"/' project.yml
    just generate

release-preflight:
    bash scripts/release-preflight.sh

release-next-version kind:
    bash scripts/release-next-version.sh {{ kind }}

release-create-rc VERSION NOTES_FILE:
    bash scripts/release-create-rc.sh {{ VERSION }} {{ NOTES_FILE }}

release-create-final VERSION RC_TAG NOTES_FILE:
    bash scripts/release-create-final.sh {{ VERSION }} {{ RC_TAG }} {{ NOTES_FILE }}

release-wait tag:
    bash scripts/release-wait.sh {{ tag }}

release-status tag:
    bash scripts/release-status.sh {{ tag }}

clean:
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf \
        .build \
        .build-ios \
        .DerivedData-ios \
        .DerivedData-mac \
        Bruce.xcodeproj

open: generate
    open Bruce.xcodeproj
