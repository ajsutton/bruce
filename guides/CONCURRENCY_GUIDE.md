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

## Burst handling and backpressure

- Choose a buffering policy from the consumer's fidelity requirement. Display-only live values
  should normally coalesce bursts and retain the newest value.
- Keep control transitions such as refreshing and reconnecting distinct from coalescible live
  values. A latest-wins buffer must not erase the signal that a real data gap occurred.
- Coalesce a pending control transition and its newest live value as one atomic buffer mutation.
  Present the control transition first, using the live value's generation and payload, so consumers
  cannot observe new data with stale decoding context.
- A custom async stream must terminate its producer exactly once whether cancellation occurs while
  waiting, while handling a buffered value, between iterations, or before the first `next()` call.
  Tie cancellation to iterator lifetime and explicitly close the stream at owner boundaries.
- Never translate an in-memory buffer overflow directly into remote I/O, history reloads, or a
  cancel-and-retry loop.
- Backfill history only for a real externally meaningful gap, such as a reconnect or an explicit
  refresh. Missing intermediate samples that cannot affect the rendered resolution are not a gap.
- Load bounded history once, append accepted live samples locally, and avoid replacing the entire
  history for each live event.
- Regression tests for bursty streams must assert both the newest presented value and the number
  of remote requests started.
- Exercise buffering with a deliberately blocked consumer so transition-loss tests are
  deterministic rather than dependent on task scheduling.
- Test cancellation at every buffer/iterator boundary and assert that the upstream subscription is
  released, not merely that the consumer task returns.

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
- Can a burst of updates amplify into repeated remote requests or whole-view recomputation?
