---
name: writing-ui-tests
description: Add, modify, or debug Bruce UI tests, screen drivers, deterministic launch state, accessibility identifiers, waits, or failure artifacts. Use for critical journeys that require real navigation, focus, accessibility, or platform presentation.
---

# Write Bruce UI Tests

Read `guides/TEST_GUIDE.md` and `guides/UI_TEST_GUIDE.md` in full before editing.

## Decide the test level

Use a unit test unless the failure requires the real UI event loop, navigation, focus,
accessibility hierarchy, or system presentation. Do not add UI tests merely for coverage.

Bruce has no UI-test target yet. Create one in `project.yml` only for a concrete critical journey,
then add a matching `just test-ui` recipe and regenerate the project.

## Structure

- Tests express a short user story through typed screen drivers.
- Drivers own `XCUIApplication` and `XCUIElement` queries.
- Centralize lowercase dot-separated identifiers.
- Add identifiers only for the current test.
- Resolve elements on every action; do not cache them across SwiftUI renders.
- Every action waits for a real post-condition with a finite timeout.
- Never use sleeps, retries, unbounded waits, or order dependencies.

Launch with deterministic arguments/state. Failure handling must capture:

- screenshot;
- accessibility hierarchy;
- action trace;
- launch arguments and seed.

## Verification

Run the narrow test first, then the full UI-test target and relevant unit suites. Repeat enough
times to establish stability; any intermittent failure is a broken test, not an acceptable flake.

Run `ui-test-review` after changing UI tests, drivers, seeds, or identifiers. Also run `ui-review`
when production views or accessibility behavior changed. Resolve every finding before committing.

