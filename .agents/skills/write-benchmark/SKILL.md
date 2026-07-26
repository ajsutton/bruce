---
name: write-benchmark
description: Add or modify a Bruce performance benchmark or os_signpost measurement for a concrete performance question. Use when repeatable timing, memory, scaling, or regression coverage is requested.
---

# Write a Benchmark

Bruce has no benchmark target today. Add benchmark infrastructure only for a concrete operation
that needs repeatable measurement, consistent with `guides/AI_ARCHITECTURE_GUIDE.md`.

## Design

1. Name the exact operation and user-visible performance risk.
2. Prefer an XCTest performance method in the closest existing test target when it can run
   deterministically.
3. Add a dedicated benchmark target and `just benchmark` recipe only when isolation or repeated
   use justifies them. Edit `project.yml`, then run `just generate`.
4. Seed deterministic data outside the measured block.
5. Measure time and memory where supported, with enough iterations to quantify variability.
6. Consume results so optimized builds cannot remove the work.

Do not benchmark network, wall-clock sleeps, random data, or setup/teardown. Do not force unwrap or
force try merely because code is in a benchmark.

Add coarse signposts only around the confirmed operation:

```swift
let signpostID = OSSignpostID(log: log)
os_signpost(.begin, log: log, name: "Operation", signpostID: signpostID)
defer { os_signpost(.end, log: log, name: "Operation", signpostID: signpostID) }
```

Run the benchmark repeatedly, capture output in `.agent-tmp/`, and use `interpret-benchmarks`.
Run `code-review` and `concurrency-review` when instrumentation touches production async code.

