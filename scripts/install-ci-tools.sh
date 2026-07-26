#!/usr/bin/env bash
set -euo pipefail

# name | version | arm64_tahoe Homebrew bottle sha256
PINNED_TOOLS=(
  "swiftlint|0.65.0|d6ce40835012e9821e8224956856f6221ae491ab379accf85f4097a92a02939f"
  "swift-format|602.0.0|df0fdcc1a40fd5424122f4db14f70df46b02de3b9046943e4155b560e79ae0df"
  "xcodegen|2.45.4|f8763683b5538a556ac4de3a86132558a086fdd976ac4088ff87d09fae1982b5"
)

TOOLS_DIR="${CI_TOOLS_DIR:-$HOME/.cache/smart-home-ci-tools}"

tool_version() {
  local name="$1"
  local binary="$2"
  case "$name" in
    swiftlint) "$binary" version ;;
    swift-format) "$binary" --version ;;
    xcodegen) "$binary" --version | sed -E 's/^Version:[[:space:]]*//' ;;
    *) return 1 ;;
  esac
}

install_bottle() {
  local name="$1"
  local version="$2"
  local expected_sha="$3"
  local binary_directory="$TOOLS_DIR/$name/$version/bin"

  if [[ ! -x "$binary_directory/$name" ]]; then
    mkdir -p "$TOOLS_DIR"
    token="$(
      curl -fsSL \
        "https://ghcr.io/token?service=ghcr.io&scope=repository:homebrew/core/$name:pull" \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['token'])"
    )"
    archive="$TOOLS_DIR/.bottle-$name.tar.gz"
    curl -fsSL \
      -H "Authorization: Bearer $token" \
      "https://ghcr.io/v2/homebrew/core/$name/blobs/sha256:$expected_sha" \
      -o "$archive"

    actual_sha="$(shasum -a 256 "$archive" | cut -d' ' -f1)"
    if [[ "$actual_sha" != "$expected_sha" ]]; then
      echo "error: $name bottle checksum mismatch" >&2
      exit 1
    fi

    tar xzf "$archive" -C "$TOOLS_DIR"
    rm -f "$archive"
  fi

  echo "$binary_directory"
}

command -v just >/dev/null 2>&1 || HOMEBREW_NO_AUTO_UPDATE=1 brew install just

for entry in "${PINNED_TOOLS[@]}"; do
  IFS='|' read -r name version expected_sha <<<"$entry"
  binary_directory="$(install_bottle "$name" "$version" "$expected_sha")"
  actual_version="$(tool_version "$name" "$binary_directory/$name")"
  if [[ "$actual_version" != "$version" ]]; then
    echo "error: expected $name $version, found $actual_version" >&2
    exit 1
  fi
  export PATH="$binary_directory:$PATH"
  [[ -n "${GITHUB_PATH:-}" ]] && echo "$binary_directory" >>"$GITHUB_PATH"
done
