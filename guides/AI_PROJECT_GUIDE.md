# AI Project Guide

## Planning

Plans and design notes live in `plans/`. Completed plans move to `plans/completed/`.

## TODOs

`TODO` and `FIXME` comments must reference an open GitHub issue:

```swift
// TODO(#123): Explain the missing behaviour.
```

Bare TODO or FIXME comments are not allowed.

## Reviewer routing

- `code-review`: production Swift, project architecture, naming, errors, optionals, and scope.
- `ui-review`: SwiftUI, native platform behaviour, strings, layout, HIG, and accessibility.
- `concurrency-review`: actors, tasks, cancellation, `Sendable`, async streams, and networking.
- `ui-test-review`: UI tests, drivers, identifiers, deterministic state, and failure artefacts.
- `appstore-review`: release metadata, project settings, privacy, entitlements, and icons.
