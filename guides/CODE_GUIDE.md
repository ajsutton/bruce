# Bruce Swift Code Guide

**Platforms:** iOS 26+ and macOS 26+
**Status:** Mandatory

This guide owns general Swift style. Concurrency, UI, and testing details live in their dedicated
guides. Apple's
[Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) are the
canonical naming reference.

## 1. Philosophy

Simplicity beats cleverness. Solve the current problem completely without generalising for
hypothetical future requirements.

- Prefer code that can be understood in one pass.
- Make invalid states difficult to represent.
- Use the platform frameworks directly until an abstraction earns its existence.
- Delete obsolete code instead of preserving compatibility that is not required.

## 2. File organisation

- One primary type per file; the filename matches the type.
- Small, closely related Codable request/response types may share a file.
- Put non-trivial protocol conformances in separate extensions, one protocol per extension.
- Compiler-synthesised conformances such as `Sendable`, `Codable`, `Equatable`, and `Hashable`
  may be declared inline on a small value type.
- Put file-private helpers in a trailing `private extension TypeName`.
- Use `// MARK: -` sections only when a file is long enough to need navigation.

## 3. Size limits

Treat these as design feedback, not formatting targets:

- Production file warning at 400 lines.
- Type warning at 250 lines.
- Function warning at 50 lines.
- Cyclomatic-complexity warning at 10.

Split by responsibility. Do not hide excess size in nested types or extensions that still form
one oversized concept.

## 4. Naming

- Types and protocols use `UpperCamelCase`.
- Functions, properties, and enum cases use `lowerCamelCase`.
- Names describe the role in the product, not the framework mechanism.
- Avoid vague containers such as `Manager`, `Helper`, `Utils`, `Data`, or `Info`.
- Name protocols for their capability or role. Do not add `Protocol` as a suffix.
- Boolean names read as assertions: `isConnected`, `canOpen`, `hasActiveAlert`.
- Use the Swift API Design Guidelines' fluent call-site rules.
- Do not repeat type information in member names.

Common suffixes:

- `View`: SwiftUI presentation.
- `Store`: observable state and user-action orchestration.
- `Client`: remote service boundary.
- `Request` / `Response`: wire types.
- `Configuration`: immutable configuration.
- `Error`: typed failure.

## 5. Types

Prefer value types by default.

Use a `struct` for:

- Domain values.
- Configuration.
- Immutable snapshots.
- Request and response payloads.

Use a class or actor when identity, shared mutable state, framework inheritance, or isolation
requires reference semantics.

- Make non-inheritable classes `final`.
- Prefer enums for finite state machines.
- Avoid untyped dictionaries where a small struct communicates the schema.
- Add `Sendable` to values crossing actor boundaries.

## 6. Protocol design

- Introduce a protocol only for a real boundary: multiple implementations, test substitution,
  platform variation, or ownership isolation.
- Keep protocols small and consumer-oriented.
- Do not create a protocol for every concrete type.
- Avoid type erasure unless an actual API requires it.
- Prefer associated types and generics for compile-time relationships.

## 7. Access control

- Default to the narrowest useful access.
- Use `private` for implementation details and `private(set)` for externally readable state.
- Do not mark declarations `public` in the application module without a concrete external
  consumer.
- Avoid `fileprivate` unless two types in the same file must cooperate.

## 8. Error handling

- Use typed errors where callers need to distinguish recovery behaviour.
- Preserve the underlying error when adding context.
- Do not silently swallow errors.
- Convert technical errors into user-facing language at the presentation boundary.
- Avoid `try?` when losing failure information changes behaviour.
- Never use `fatalError` for recoverable input, state, or network failures.

## 9. Optionals

- Use `guard` for required preconditions and early exits.
- Use `if let` when the optional naturally scopes one branch.
- Do not force unwrap production values.
- Do not use sentinel values such as an empty string where `nil` expresses absence.
- Avoid optional booleans; use an enum when there are genuinely three states.

## 10. Initialisers

- Keep initialisers cheap and free of hidden asynchronous work.
- Require dependencies and invariant values explicitly.
- Use defaults only when they are safe and unsurprising.
- Prefer static factory methods when construction is fallible or asynchronous.

## 11. Extensions

- Extend a type to organise behaviour or adopt a protocol, not to conceal an oversized type.
- Avoid feature-local extensions on Foundation and standard-library types; they leak across the
  module.
- Put genuinely generic shared extensions in a clearly named shared location and test them.

## 12. Closures

- Use trailing-closure syntax when it improves the call site.
- Capture `self` deliberately in escaping closures.
- Use `[weak self]` only when a retained cycle is possible or the task must not extend lifetime.
- Do not add `[weak self]` mechanically to structured tasks whose lifetime is owned and bounded.
- Prefer named functions when a closure contains multiple conceptual steps.

## 13. Collections

- Prefer `first(where:)` over `filter(...).first`.
- Prefer `contains(where:)` over filtering and checking emptiness.
- Prefer `min` or `max` over sorting solely to take one element.
- Use `reduce(into:)` for mutable aggregation.
- Do not call `enumerated()` when the index is unused.
- Do not use `map { $0 }` to materialise a sequence; use `Array(sequence)`.
- Avoid building intermediate arrays in hot paths when a lazy chain is clear.

## 14. Control flow

- Prefer early returns to deep nesting.
- Use `switch` for finite state and ensure cases are exhaustive.
- Do not add a `default` case when enumerating an app-owned enum; the compiler should identify
  newly added cases.
- Extract complex conditions into well-named properties or functions.

## 15. Dependency injection

- Pass dependencies explicitly at the narrowest stable boundary.
- SwiftUI environment injection is appropriate for app- or scene-scoped dependencies.
- Avoid global mutable singletons.
- Do not introduce a dependency container until multiple real dependencies require one.

## 16. SwiftUI idioms

- Views are value types and should remain cheap to create.
- Do not perform I/O or launch unstructured work from a view initialiser.
- Use `.task` for lifecycle-bound asynchronous work.
- Keep long-running or multi-step actions in an observable store or focused model.
- Prefer semantic styles and platform controls over custom replicas.
- Avoid `AnyView`; use `@ViewBuilder`, generics, or concrete composition.

## 17. Documentation

Document decisions and contracts, not syntax.

Use `///` for:

- Public or widely reused APIs.
- Non-obvious invariants.
- Parameters whose unit or interpretation is not clear from the type.
- Safety- or security-sensitive behaviour.

Do not preserve historical implementation commentary. Git already records history.

## 18. TODOs and FIXMEs

Every TODO or FIXME references an open issue:

```swift
// TODO(#123): Retry authentication after the credential flow is implemented.
```

Do not use TODOs to defer code-review findings without explicit user approval.

## 19. Imports

- Import only modules used by the file.
- Let swift-format order imports.
- Application-domain values should not import SwiftUI.
- Keep platform-specific imports inside `#if os(...)` only when the file genuinely supports both
  platforms.

## 20. Formatting

`swift-format` owns layout. SwiftLint owns policy and idiom rules.

```sh
just format
just format-check
```

Do not hand-format against the formatter, add a lint baseline, or weaken lint thresholds to pass
a change.
