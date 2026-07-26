# Concurrency Guide

## Isolation model

- UI-bound observable state is `@MainActor`.
- Immutable values crossing isolation boundaries conform to `Sendable`.
- Use actors for shared mutable state that is not UI-bound.
- Prefer structured concurrency and `async/await`.
- Make ownership and cancellation explicit.

## Tasks

- Use SwiftUI `.task` for work owned by a view's lifecycle.
- Store a task handle when later work must cancel or replace it.
- Check cancellation before publishing expensive results.
- Avoid detached tasks unless actor inheritance is specifically incorrect and the boundary is
  documented.
- Never use `Task` merely to silence an isolation error.

## Parallel work

Use `async let` for a fixed set of independent operations. Use a task group for a dynamic set.
Do not parallelise dependent steps or mutations whose ordering is part of correctness.

## Streams and connections

- Treat connection state as an explicit state machine.
- Bound reconnect backoff and make cancellation stop reconnect attempts.
- Ensure only the current connection can publish state.
- Finish streams and release continuations when their owner shuts down.
- Do not silently drop decoding, authentication, or protocol errors.

## Stale-result protection

When an asynchronous operation can be superseded:

1. Capture the input or generation that started it.
2. Perform the work.
3. Before publishing, verify the input is still current.

Cancellation alone is insufficient because some underlying operations do not stop immediately.

## Testing

- Run UI-bound tests on `@MainActor`.
- Test cancellation, replacement, reconnection, and stale-result paths.
- Use deterministic clocks or injected timing where backoff/debounce behaviour matters.
- Never add sleeps to concurrency tests.

## Review checklist

- Which actor owns each mutable value?
- Can an older task overwrite newer state?
- Who cancels long-running work?
- Does object lifetime accidentally extend because a task retains it?
- Are values crossing actors actually `Sendable`?
- Can a stream or continuation leak?
