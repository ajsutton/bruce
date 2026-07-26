---
name: fixing-format-check
description: Diagnose and fix Bruce `just format-check`, swift-format, or SwiftLint failures. Also use before changing `.swiftlint.yml`, adding lint suppressions, changing thresholds, or creating a baseline.
---

# Fix Format Check

Read `guides/CODE_GUIDE.md` before making semantic lint fixes.

## Reproduce

```bash
mkdir -p .agent-tmp
just format-check 2>&1 | tee .agent-tmp/format-check.txt
```

Separate failures into:

- `swift-format`: apply mechanically with `just format`.
- SwiftLint: understand the rule and fix the source design.

## Non-negotiable policy

Bruce has no SwiftLint baseline. Never:

- add a baseline or `--baseline`;
- run `swiftlint --write-baseline`;
- raise a threshold to hide a violation;
- add a disable comment for a fixable violation.

If a legitimate exception would materially expand scope, stop and ask the user.

## Finish

1. Run `just format`.
2. Review the diff for unintended semantic changes.
3. Run `just format-check`.
4. Run relevant builds/tests for semantic fixes.
5. Run the repository's required reviewer cycle.
6. Confirm `.swiftlint.yml` and baseline files were not changed unintentionally.

