---
name: automate-app
description: Launch or inspect the running Bruce macOS app without operating its UI. Use for runtime logs, process verification, or preparing a worktree build for user-driven review.
---

# Inspect the Bruce App

Automate the debug build from the current worktree, never an installed copy.

## Resolve the app first

```bash
root="$(git rev-parse --show-toplevel)"
app="$root/.build/Build/Products/Debug/Bruce.app"
binary="$app/Contents/MacOS/Bruce"
test -x "$binary" || just build-mac
```

Before launching, check for another Bruce instance:

```bash
ps ax -o pid=,command= | rg '[B]ruce.app/Contents/MacOS/Bruce' || true
```

If another instance is running, resolve its executable with `lsof -p <pid> -d txt`.
Do not launch a second instance silently. Stop and tell the user which bundle is running.
Launch the verified worktree bundle only after this check.

## Choose the automation surface

1. Use Xcode previews for visual verification; follow the `reviewing-ui-with-preview` skill.
2. Use Xcode UI tests for repeatable regression coverage; follow the `writing-ui-tests` skill.
3. Use `just run-mac-with-logs` when runtime evidence matters.

Do not operate the app through desktop-control tools, accessibility scripting, injected mouse or
keyboard events, or screen-coordinate clicks. You may launch the worktree app for user review, but
the user must navigate and interact with it.

Bruce does not currently expose an AppleScript dictionary. Do not copy Moolah AppleScript
commands or add an automation API without a concrete product use case. If the user explicitly
requests AppleScript, explain this boundary and use previews or UI tests as appropriate.

## Verification

- Keep launch arguments and test state deterministic.
- Capture screenshots or logs in `.agent-tmp/`.
- Confirm the active executable belongs to this worktree.
- Record the exact runtime state inspected or user-reported interaction.
- Stop only processes started for the verification.
