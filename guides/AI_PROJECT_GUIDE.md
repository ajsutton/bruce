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
- `data-access-review`: initial and live remote values, freshness, stale presentation,
  reconnection, optimistic writes, and data-flow lifecycle.
- `home-assistant-connection-review`: Home Assistant OAuth, credentials, HTTP/WebSocket transport,
  connection state, retry, heartbeat, routing, resubscription, and reconnect energy use.
- `ui-test-review`: UI tests, drivers, identifiers, deterministic state, and failure artefacts.
- `appstore-review`: release metadata, project settings, privacy, entitlements, and icons.
