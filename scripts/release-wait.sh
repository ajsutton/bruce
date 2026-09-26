#!/usr/bin/env bash
# Polls the workflow run associated with a tag until terminal.
# Exits zero on success; the workflow's conclusion code otherwise.
#
# Usage: release-wait TAG
set -euo pipefail

[[ "$#" -eq 1 ]] || {
    printf 'Usage: %s TAG\n' "$(basename "$0")" >&2
    exit 2
}

tag="$1"

# Determine which workflow file matches the tag pattern.
if [[ "$tag" == *-rc.* ]]; then
    workflow="release-rc.yml"
else
    workflow="release-final.yml"
fi

source "$(dirname "${BASH_SOURCE[0]}")/lib/release-common.sh"
# Poll up to 3 minutes for the workflow run to materialise.
run_identity=""
for _ in {1..90}; do
    run_identity=$(find_release_run "$tag" "$workflow")
    [[ -n "$run_identity" ]] && break
    sleep 2
done

if [[ -z "$run_identity" ]]; then
    printf 'no workflow run found for %s on %s after 180s\n' "$workflow" "$tag" >&2
    printf 'check the Actions tab and re-run "just release-wait %s" once the run appears\n' \
        "$tag" >&2
    exit 1
fi

read -r run_id attempt <<< "$run_identity"

printf 'watching %s run %s for tag %s\n' "$workflow" "$run_id" "$tag"
if [[ -z "$attempt" ]]; then
    gh run watch "$run_id" --exit-status
else
    # A rerun creates another RC: never report its result for this older release.
    while true; do
        run_status=$(gh run view "$run_id" --attempt "$attempt" --json status,conclusion)
        status=$(jq -r .status <<< "$run_status")
        printf '  attempt %s: %s\n' "$attempt" "$status"
        if [[ "$status" == "completed" ]]; then
            conclusion=$(jq -r .conclusion <<< "$run_status")
            printf '  conclusion: %s\n' "$conclusion"
            [[ "$conclusion" == "success" ]]
            exit
        fi
        sleep 10
    done
fi
