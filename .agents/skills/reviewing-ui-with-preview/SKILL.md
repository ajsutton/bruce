---
name: reviewing-ui-with-preview
description: Iterate on a Bruce SwiftUI view with Xcode previews for visual design, layout, focus, interaction, accessibility, and rapid user feedback. Use when the task is local to a view or explicitly mentions the Xcode canvas or #Preview.
---

# Review UI With Xcode Previews

Read `guides/UI_GUIDE.md` and `guides/BRAND_GUIDE.md` before editing.

## Setup

1. Run `just generate`.
2. Open `Bruce.xcodeproj` and the target Swift file in Xcode.
3. Identify the correct project/window when multiple worktrees are open.
4. Render the file's `#Preview` with the available Xcode integration. If no integration is
   available, ask the user to open the canvas and share a screenshot.

Retry one preview invalidation after generation or an edit; repeated failures require diagnosis.

## Iteration loop

1. Make one focused view change.
2. Render the same preview.
3. Inspect the image for clipping, spacing, truncation, contrast, platform behavior, and
   accessibility implications.
4. Share the concrete result and incorporate user feedback.

Preview the sheet or popover content directly when a static host cannot present it. Do not change
production layout to compensate for preview-canvas whitespace.

Keep shared view code valid on both iOS and macOS. Guard AppKit/UIKit-only preview code.

When the behavior needs a real window, navigation stack, Dock, system presentation, or runtime
service, launch the worktree app for user review without operating its UI. Use
`run-mac-app-with-logs` when logs matter.

Before finishing, remove preview-only scaffolding and run format, relevant builds/tests,
`ui-review`, and any other required reviewers.
