---
name: landing-prs
description: Land a Bruce GitHub pull request through the repository's merge queue, including stacked PR ordering, CI monitoring, failure handling, and post-merge worktree cleanup.
---

# Land Pull Requests

Use the bundled scripts from the canonical Codex-compatible path:

```bash
.agents/skills/landing-prs/scripts/land-pr.sh <PR>
```

The entry point resolves the PR base:

- A PR targeting `main` gets auto-merge enabled and is watched until `mergedAt` is present.
- A stacked PR waits for its parent to merge, retargets to `main`, then enables auto-merge.

Never enable auto-merge on a child while it still targets its parent's feature branch.

## Monitor

The launcher backgrounds a watcher and writes:

```text
.agent-tmp/landing-prs/watch-<PR>.log
```

Tail that log until merge or a fix-required terminal state. A zero exit from `land-pr.sh` means
the watcher started, not that the PR merged.

Useful commands:

```bash
ps ax -o pid=,command= | rg '[w]atch-pr.sh'
tail -f .agent-tmp/landing-prs/watch-<PR>.log
kill <watcher-pid>
```

The scripts accept `--repo OWNER/REPO` when run outside the checkout. They require authenticated
`gh` and `jq`. Bruce CI subscribes to `merge_group`, so queued commits receive required checks.

After confirmed merge, remove a worktree only when it is clean and all changes are recoverable.
Never force-remove a dirty worktree.
