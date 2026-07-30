# UI Guide

Brand expression, palette, language and the Bruce/Full Bruce presentation modes follow
`BRAND_GUIDE.md`.

## Principles

- The app should feel native on each platform.
- iPhone and Mac may share components, but not at the expense of platform conventions.
- Build screens around a concrete household task rather than around Home Assistant entities.
- Keep the primary path obvious for family members who do not manage the system.
- Reveal advanced detail progressively.
- Use colour to communicate state and exceptions, not as decoration.
- Keep navigation, control placement and meaning identical across Bruce presentation modes.
- Treat Go The Full Bruce as coordinated app icon, styling and eligible-language presentation,
  not as a separate feature set.
- Restore the user's durable UI context after app restarts, including selected tabs and navigation,
  whenever that context remains available and appropriate.

## Platform behaviour

### iPhone

- Optimise for one-handed use and 44-point minimum touch targets.
- Put the most common actions within comfortable reach.
- Prefer navigation stacks, sheets, and standard toolbars.
- Support Dynamic Type without clipping or fixed text heights.

### macOS

- Support keyboard navigation and standard shortcuts.
- Use sidebars, inspectors, tables, and menus only when the use case benefits from them.
- Toolbar, menu, and context-menu actions should agree.
- Disable unavailable commands rather than changing menu shape.

### App settings

- Put every persistent app setting in the native Settings window on macOS and in the Settings app
  on iOS.
- Do not place app settings in primary app content or duplicate them in another in-app surface.
- Keep task controls that act on the house in the relevant app screen; they are not app settings.

## SwiftUI

- Prefer native controls and semantic system colours.
- Avoid fixed widths for text.
- Use `ContentUnavailableView` for empty or unavailable states.
- Use `Form` for editable settings and structured input.
- Use `confirmationDialog` or alerts for destructive and safety-sensitive actions.
- Do not reproduce system controls with custom gestures unless the native control cannot satisfy
  the use case.
- Respect Reduce Motion and increased contrast.

## Status and control

- Distinguish live, stale, unavailable, and in-progress state.
- Do not display cached state as though it were live.
- Present server-wide state once in the window instead of repeating it in every panel or card. Put
  connection errors at the top, where they need attention.
- Keep routine server state such as live, connecting, or updating in a subtle footer so transitions
  do not move the panel content. Do not show a last-updated time while the update is recent; reveal
  its age only when it adds useful freshness context.
- Keep panel- and device-specific failures beside the affected content or control. When cached
  values remain visible, continue to identify them as last known in their visual and accessibility
  presentation without duplicating the server-wide status message.
- Prefer integrating write controls with the current-status display they change. Use a separate
  control when the integrated affordance would be unclear, hard to discover, or awkward to use.
- Provide immediate acknowledgement for every command.
- Use optimistic updates for routine, reversible controls when failure can be rolled back clearly.
  Keep the selected state, descriptive text, and surrounding layout stable while confirmation is in
  flight; roll back and show an error only when the server rejects the command or a reasonable
  confirmation timeout expires.
- Do not flash progress indicators for operations that usually finish quickly. Delay them by a
  short grace period, keep them visually compact, and reserve their layout space so appearing or
  disappearing does not move nearby content.
- Avoid optimistic updates for safety-sensitive actions unless the pending state is explicit.
- Confirm remote or safety-sensitive operations; do not confirm routine reversible actions.

## Time-series displays

- Match update fidelity to the visible chart resolution. Coalesce samples that cannot produce a
  distinct rendered point.
- Retain the newest sample in each coalescing window and flush a lone trailing sample at the
  window boundary. Publish availability and other semantic state transitions immediately.
- Observe each live store at the narrowest view subtree that needs it. A container that only passes
  a store to independently observed children must not invalidate every child for every update.
- Pass observable stores through ancestor containers as plain values when those ancestors do not
  read the store. Avoid assigning unchanged `@Published` values because those assignments still
  invalidate observers.
- For high-rate values, retain full-precision source state for control and data decisions but only
  publish when the displayed value or another visible property changes.
- Put expensive repeated live cards behind an explicit equality boundary that covers every visible
  input. Keep callbacks out of equality only when their owner and behaviour remain stable.
- Lazily construct vertically stacked panels so off-screen live features do not participate in
  layout and rendering work.
- Load a bounded historical interval once, then append accepted live samples instead of
  refetching and republishing the full interval for every update.
- Do not refetch history merely because an intermediate live update was dropped. Reserve backfill
  for reconnects, explicit refreshes, or another user-visible data gap.
- Profile chart updates with representative history. Verify CPU, wakeups, request cadence, and
  main-thread work before treating a live chart as complete.

## Accessibility

- Give custom controls meaningful labels, values, and traits.
- Do not rely on colour alone.
- Keep contrast at least 4.5:1 for body text and 3:1 for large text.
- Combine child accessibility elements only when the combined reading is clearer.
- Verify keyboard use on macOS and VoiceOver order on iOS.

## Review checklist

- Is this the smallest UI that solves the use case?
- Does it use native platform navigation and controls?
- Are loading, stale, unavailable, error, and success states represented?
- Do routine state changes remain visually stable without selection, text, spinner, or layout
  flicker?
- Can bursty live data be coalesced without visible loss, and does it avoid repeated history I/O?
- Does coalescing also apply while initial or refresh history is loading?
- Are live-store observation, published-value, and repeated-card equality boundaries narrow enough
  to prevent unrelated or visually identical updates from rebuilding the screen?
- Does the app restore the user's durable UI context after a restart?
- Are dangerous actions appropriately protected?
- Does it work with Dynamic Type, VoiceOver, keyboard navigation, dark mode, and Reduce Motion?
