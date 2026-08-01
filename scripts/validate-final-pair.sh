#!/usr/bin/env bash
set -euo pipefail

[[ "$#" -eq 5 ]] || {
    echo "Usage: $0 VERSION REQUESTED_RC LATEST_RC FINAL_SHA RC_SHA" >&2
    exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/release-common.sh"

validate_final_pair "$@"
