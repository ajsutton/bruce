---
name: profile-performance
description: Diagnose Bruce performance problems such as UI freezes, beachballs, hangs, slow transitions, high CPU, or suspicious runtime timing. Use stack samples, unified logs, and Instruments before optimizing.
---

# Profile Bruce Performance

Gather evidence before changing code.

## Stack sample

```bash
mkdir -p .agent-tmp
pids=($(pgrep -f 'Bruce.app/Contents/MacOS/Bruce'))
test "${#pids[@]}" -eq 1
pid="${pids[0]}"
sample "$pid" 3 -f .agent-tmp/sample-output.txt
```

Focus on `com.apple.main-thread` and frames with the largest sample counts.
Prefer the exact app PID printed by `just run-mac-with-logs`; use discovery only when exactly one
Bruce process is running.

## Unified logs

Use `run-mac-app-with-logs`, reproduce the issue, then search
`.agent-tmp/app-logs.txt` by category, error text, or timing marker. Do not start the logging
recipe with `&`; its non-interactive mode already detaches.

## Instruments

```bash
xctrace list templates
xctrace record --template 'Time Profiler' \
  --attach "$pid" \
  --time-limit 10s \
  --output .agent-tmp/profile.trace
open .agent-tmp/profile.trace
```

Use Allocations or Leaks only when memory evidence points there. Add coarse `os_signpost`
instrumentation around a confirmed operation; do not scatter speculative signposts.

## Report

State the reproduction, build/device, sample or trace evidence, dominant frames, and measured
before/after result. Keep captures in `.agent-tmp/` and stop only processes started for profiling.
