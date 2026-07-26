# AI Architecture Guide

## Current architecture

- Target iOS 26+ and macOS 26+.
- SwiftUI is the native UI framework.
- iOS and macOS share code only where the shared design remains natural.
- There is currently no persistence, networking, backend, or feature architecture.

Do not pre-emptively create layers. Introduce boundaries when the first concrete use case makes
their responsibilities clear.

## Incremental development

- Build one useful vertical slice at a time.
- Avoid generic dashboards, entity browsers, configurable card systems, and server-driven UI.
- Do not add a protocol until there is a real substitution boundary.
- Do not add a shared abstraction merely because two future platforms might need it.
- Keep platform-specific UI separate when native behaviour differs.

## Thin views

Views render state and dispatch user actions. When a view accumulates multi-step orchestration,
error mapping, or reusable transformation, extract that responsibility into a focused model or
store and cover it with tests.

Local presentation state such as selection, sheet visibility, and focus can remain in the view.

## Testing

- Follow `TEST_GUIDE.md`; UI tests also follow `UI_TEST_GUIDE.md`.
- Prefer tests for behaviour and state transitions over implementation structure.
- Test failure and cancellation paths for asynchronous work.
