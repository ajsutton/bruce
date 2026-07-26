# AI Assistant Guide

These rules apply to every AI coding tool used in this repository.

## Quality gate

AI reviewer agents are the required quality gate.

- Run the relevant reviewers before committing code.
- Do not skip review because a change is small.
- Treat every finding as a request to fix the code.
- After fixing findings, repeat review until the relevant reviewers report no findings.

Use at least `code-review` after modifying production Swift. Add:

- `ui-review` for SwiftUI, user-facing strings, layout, interaction, or accessibility.
- `concurrency-review` for async code, tasks, actors, networking, or `Sendable`.
- `ui-test-review` for UI tests, screen drivers, seeds, or accessibility identifiers.
- `appstore-review` before release tagging.

## Working style

- Build only what the current use case requires.
- Prefer a complete vertical slice over speculative infrastructure.
- Keep durable rules in `guides/`; keep assistant-specific entry points short.
- Use `just` targets for generation, formatting, builds, and tests.
- Store temporary logs and artefacts in `.agent-tmp/`.
- Never edit `SmartHome.xcodeproj` directly.
- Never add database, iCloud, Android, Watch, widget, App Intent, or CarPlay infrastructure
  without a concrete requirement.
