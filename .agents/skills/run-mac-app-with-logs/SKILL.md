---
name: run-mac-app-with-logs
description: Run the Bruce macOS app while capturing unified logs for crashes, hangs, unexpected behavior, startup diagnostics, or verification of OSLog statements.
---

# Run Bruce With Logs

Start the worktree build:

```bash
# Default Bruce subsystem
just run-mac-with-logs

# Custom unified-log predicate
just run-mac-with-logs 'category == "BrandMode"'
```

The recipe launches Bruce suspended, subscribes a PID-filtered log stream, then resumes it so
startup messages are captured. Logs go to `.agent-tmp/app-logs.txt`.

In an interactive terminal it runs until Ctrl-C and cleans up. In non-interactive agent execution,
the recipe returns after detaching Bruce and the log stream. Do not add `&`.

If Bruce is already running, stop or use that instance rather than silently launching another.

Inspect with:

```bash
wc -l .agent-tmp/app-logs.txt
rg -i 'error|failed|fault' .agent-tmp/app-logs.txt
tail -f .agent-tmp/app-logs.txt
```

OSLog dynamic values are private unless marked `.public`. Do not weaken privacy merely for
diagnostics.

Use the exact PIDs printed by the recipe for cleanup. As a fallback:

```bash
kill <app-pid> 2>/dev/null || true
kill <log-stream-pid> 2>/dev/null || true
```

If those PIDs were not recorded, enumerate candidates and verify the Bruce executable path and
log-stream predicate before terminating anything.

Check unexpected exits under `~/Library/Logs/DiagnosticReports/`.
