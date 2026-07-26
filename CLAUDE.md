# Claude Instructions — Bruce

Read `guides/AI_ASSISTANT_GUIDE.md` before changing files. Shared workflow, architecture,
project-management, and review rules live under `guides/`.

Claude review agents live in `.claude/agents/`. Their findings follow
`guides/AI_REVIEW_GATE_GUIDE.md` and must be fixed before committing.

`Bruce.xcodeproj` is generated. Edit `project.yml` and run `just generate`; never edit the
generated project directly.

For every implementation task, run the required formatting, builds, tests, and reviewer cycle,
then commit all intended changes before reporting completion. Do not leave a completed task as an
uncommitted working-tree diff unless the user explicitly asks for that.
