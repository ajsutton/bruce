# UI Test Guide

Read `TEST_GUIDE.md` first. UI tests inherit all of its rules.

## When to add a UI test

Use a UI test for a critical user journey whose behaviour depends on real navigation, focus,
accessibility, or platform presentation and cannot be proven with a lower-level test.

Do not add UI tests merely to increase coverage.

## Screen-driver rule

Tests describe user stories and call typed screen-driver methods. Tests do not query
`XCUIApplication` or `XCUIElement` directly.

Drivers:

- Own element lookup.
- Use central accessibility-identifier constants.
- Record each user action.
- Wait for a real post-condition with a finite timeout.
- Resolve elements on each use rather than caching them across SwiftUI renders.

## Identifiers

- Use lowercase dot-separated identifiers: `climate.zone.masterBed`.
- Store identifiers in one registry.
- Never place raw identifier strings in test methods.
- Add an identifier only when a current test needs it.
- Accessibility labels and test identifiers serve different purposes; keep both.

## Reliability

UI tests must not contain sleeps, retry loops, unbounded waits, or order dependencies.

Every failure should capture enough information to debug without rerunning:

- Screenshot.
- Accessibility hierarchy.
- Action trace.
- Launch arguments and deterministic seed.

## Reviewer

Run `ui-test-review` after changing UI tests, drivers, deterministic seeds, or accessibility
identifiers.
