---
name: cutting-a-release
description: Prepare or cut a Bruce release candidate or final release, draft release notes, bump versions, or create a release tag. Use when the user asks to ship, tag, publish, or prepare a release.
---

# Cut a Bruce Release

Bruce does not yet have a checked-in release runbook or release automation targets. Treat that as
a hard boundary: do not invent signing, upload, notarization, App Store, or tag procedures during
a release.

## Preparation

1. Read `guides/BRAND_GUIDE.md` and draft concise user-facing notes from commits since the last
   release tag.
2. Read version settings from `project.yml`. Change them there, never in `Bruce.xcodeproj`.
3. Run the pre-commit workflow from `guides/AI_WORKFLOW_GUIDE.md`.
4. Run `appstore-review` and every other reviewer required by the changed release files. Resolve
   every finding.
5. Store draft notes and inspection output in `.agent-tmp/`.

## Release boundary

Before creating a tag, uploading a build, or changing release state:

- show the proposed version, commit SHA, tag, and release notes;
- identify the exact signing and distribution path;
- obtain explicit user approval for those actions.

If the user wants repeatable release execution, create `guides/RELEASE_GUIDE.md` and matching
`just` targets as a separate reviewed change before cutting the release. Once that runbook exists,
follow it exactly and treat it as the source of truth.

