#!/usr/bin/env bash
# Prints a human-readable summary of a release's workflow and GitHub assets.
#
# Usage: release-status TAG
set -euo pipefail

[[ "$#" -eq 1 ]] || {
    printf 'Usage: %s TAG\n' "$(basename "$0")" >&2
    exit 2
}

tag="$1"

if [[ "$tag" == *-rc.* ]]; then
    workflow="release-rc.yml"
else
    workflow="release-final.yml"
fi

printf '== Release %s ==\n' "$tag"

# GH release.
if gh release view "$tag" >/dev/null 2>&1; then
    printf '\nGitHub release:\n'
    gh release view "$tag" --json tagName,isPrerelease,createdAt,assets \
        --jq '"  tag:        \(.tagName)\n  prerelease: \(.isPrerelease)\n  created:    \(.createdAt)\n  assets:     \([.assets[].name] | join(", "))"'
else
    printf '\nGitHub release: NOT FOUND\n'
fi

source "$(dirname "${BASH_SOURCE[0]}")/lib/release-common.sh"

# Workflow run.
printf '\nWorkflow:\n'
run_identity=$(find_release_run "$tag" "$workflow" || true)
run_status=""
if [[ -n "$run_identity" ]]; then
    read -r run_id attempt <<< "$run_identity"
    view_args=(run view "$run_id" --json status,conclusion,databaseId,createdAt,attempt)
    [[ -z "$attempt" ]] || view_args+=(--attempt "$attempt")
    run_status=$(gh "${view_args[@]}")
fi
if [[ -z "$run_status" || "$run_status" == "null" ]]; then
    printf '  no run found for %s\n' "$workflow"
else
    printf '%s' "$run_status" \
        | jq -r '"  workflow:   '"$workflow"'\n  run id:     \(.databaseId)\n  attempt:    \(.attempt)\n  status:     \(.status)\n  conclusion: \(.conclusion // "-")\n  created:    \(.createdAt)"'
fi
