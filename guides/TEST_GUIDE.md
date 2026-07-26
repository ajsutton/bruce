# Test Guide

## Philosophy

Tests describe user-visible or externally observable behaviour. They should remain deterministic,
fast, and useful when they fail.

## Rules

- One behaviour per test.
- Use plain-English test names such as `testClosingAnOpenGarageUpdatesItsState`.
- Arrange, act, and assert clearly without mandatory section comments.
- Test through the public API of the subject.
- Assert exact relevant values, not broad implementation details.
- Include failure and cancellation paths for asynchronous work.
- Do not add test-only branches to production code.

## No flake tolerance

Never use:

- `Thread.sleep`, `sleep`, or `usleep`.
- Arbitrary delayed dispatch.
- Unbounded waits.
- Automatic retries or flaky-test annotations.

Wait for the exact observable condition with a finite timeout. A flaky test is broken and must be
fixed or removed before merging.

## Test types

- Unit tests for values, transformations, stores, and state machines.
- Integration tests for real boundaries such as network protocol handling.
- UI tests only for critical user journeys that cannot be proven below the UI layer.

## Running tests

```sh
just test
just test-mac
just test-ios
just test-mac SomeTests/testBehaviour
```

Capture significant runs in `.agent-tmp/`.

## Checklist

- Does the name describe behaviour?
- Does the test cover one behaviour?
- Is the failure message actionable?
- Is it deterministic across time zones, locales, devices, and execution order?
- Does it avoid sleeps, retries, and unbounded waits?
- Would an internal refactor leave the test valid?
