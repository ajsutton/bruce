---
name: developing-on-linux
description: Work on Bruce from Linux where Xcode and Apple SDKs are unavailable. Use when Swift tools are missing, CI is being debugged from Linux, or formatting and lint checks must be reproduced without macOS.
---

# Develop on Linux

Bruce's application builds and tests require Xcode on macOS. Linux can still validate formatting,
lint policy, shell scripts, YAML, and platform-independent code.

## Match CI tools

Read current versions from `scripts/install-ci-tools.sh`; do not copy versions from this skill.
Install the matching Swift toolchain and SwiftLint release for the Linux distribution.
`swift-format 602.x` corresponds to the Swift 6.2 toolchain.

SwiftLint needs the toolchain's `libsourcekitdInProc.so`, normally exposed through
`LD_LIBRARY_PATH`.

## Run available checks

Mirror the justfile's tracked scope:

```bash
find App Tests -type f -name '*.swift' -print0 \
  | xargs -0 swift-format format -i --configuration .swift-format
while IFS= read -r -d '' file; do
  cmp -s "$file" <(swift-format format --configuration .swift-format "$file") \
    || echo "NOT FORMATTED: $file"
done < <(find App Tests -type f -name '*.swift' -print0)
swiftlint lint --strict --no-cache
bash -n scripts/*.sh
git diff --check
```

If `just format-check` itself cannot run, compare each Swift file with formatted stdout using
`cmp`, matching the recipe in `justfile`.

## Boundaries

- SwiftUI, AppKit, UIKit, asset compilation, XcodeGen output, signing, and XCTest execution remain
  macOS-only.
- Do not add Linux product targets or conditional production architecture merely to satisfy a
  Linux check.
- A Linux type-check is useful only for a genuinely Foundation-only subset. State its limited
  scope and still require macOS CI.
