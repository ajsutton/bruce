# AI Review Gate Guide

This policy applies to every reviewer agent in this repository.

## Findings are fix requests

A finding has two valid outcomes:

1. The author fixes it.
2. The author gives a concrete technical rebuttal and the reviewer withdraws it.

Do not create a "follow up later" category. If a finding is too large for the current change,
stop and obtain explicit user approval before deferring it.

After fixes, rerun the relevant review until it reports no findings.

## Fix the class of issue

When a finding identifies a repeated unsafe pattern, search the repository for every occurrence
and fix the whole class rather than only the reported line.

When the defect is split lifecycle ownership, fixing the class means establishing one authoritative
control plane and removing competing recovery decisions. A callback for one trigger is not a valid
fix merely because it has regression coverage. Follow a task-specific architecture guide over a
general preference for a smaller diff.
