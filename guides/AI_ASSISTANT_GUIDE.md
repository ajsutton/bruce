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
- `data-access-review` for remote-data clients, streams, live updates, freshness, stale values,
  optimistic writes, or data-backed presentation.
- `ui-test-review` for UI tests, screen drivers, seeds, or accessibility identifiers.

Release candidate and final-release tagging use the approval and verification gates in
`RELEASE_GUIDE.md`; tagging alone does not require a reviewer.

## Working style

- Build only what the current use case requires.
- Prefer a complete vertical slice over speculative infrastructure.
- Keep durable rules in `guides/`; keep assistant-specific entry points short.
- Use `just` targets for generation, formatting, builds, and tests.
- Store temporary logs and artefacts in `.agent-tmp/`.
- Never edit `Bruce.xcodeproj` directly.
- Never add database, iCloud, Android, Watch, widget, App Intent, or CarPlay infrastructure
  without a concrete requirement.

## UI verification

- Use Xcode previews for visual UI iteration and verification.
- Do not operate the app through OS-level UI automation, accessibility scripting, injected mouse
  or keyboard events, or screen-coordinate clicks.
- An assistant may launch the worktree app for user review, but must leave navigation and
  interaction to the user.
- When a runtime-only state cannot be represented in a preview, add deterministic preview data or
  ask the user to navigate and report what they observe.
