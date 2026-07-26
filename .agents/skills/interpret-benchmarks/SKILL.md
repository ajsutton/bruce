---
name: interpret-benchmarks
description: Interpret Bruce performance measurements or XCTest benchmark output, compare runs, assess noise and scaling, and decide whether evidence warrants optimization. Use whenever benchmark numbers or a suspected regression need analysis.
---

# Interpret Benchmarks

Bruce has no benchmark target or `just benchmark` recipe yet. If the user supplies measurements,
analyze them directly. If repeatable measurement is required, use `write-benchmark` to add only the
smallest benchmark justified by the current performance question.

## Analysis

For every measurement, capture:

- operation and data size;
- build configuration and device;
- mean or median;
- individual samples;
- relative standard deviation;
- memory when relevant.

Treat variability before differences:

- under 5%: small comparisons may be meaningful;
- 5–10%: generally usable;
- 10–20%: only large changes are credible;
- over 20%: fix the measurement before drawing conclusions.

Compare scale tiers with `larger / smaller`. Roughly 1x suggests constant work, around 2x suggests
linear scaling when data doubles, and materially above 2x warrants profiling.

Do not optimize from a single noisy run. Use `profile-performance` to locate the expensive code
path, change one cause, then repeat the same measurement.

Report the environment, samples, summary statistic, variability, scale ratio, and conclusion.
Store captured output in `.agent-tmp/`.

