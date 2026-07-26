---
name: automate-app
description: Drive or inspect the running Bruce macOS app end to end. Use for one-off UI verification, screenshots, navigation, or reproducing an interaction in the worktree build. Also use when a task mentions AppleScript or terminal-driven app automation.
---

# Automate the Bruce App

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

1. Use an available desktop-control tool for one-off interaction and visual verification.
2. Use Xcode UI tests for repeatable regression coverage; follow the `writing-ui-tests` skill.
3. Use `just run-mac-with-logs` when runtime evidence matters.

Bruce does not currently expose an AppleScript dictionary. Do not copy Moolah AppleScript
commands or add an automation API without a concrete product use case. If the user explicitly
requests AppleScript, explain this boundary and use UI automation when available.

## Verification

- Keep launch arguments and test state deterministic.
- Capture screenshots or logs in `.agent-tmp/`.
- Confirm the active executable belongs to this worktree.
- Record the exact interaction and observed result.
- Stop only processes started for the verification.
