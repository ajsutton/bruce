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
- Prefer integrating write controls with the current-status display they change. Use a separate
  control when the integrated affordance would be unclear, hard to discover, or awkward to use.
- Provide immediate acknowledgement for every command.
- Avoid optimistic updates for safety-sensitive actions unless the pending state is explicit.
- Confirm remote or safety-sensitive operations; do not confirm routine reversible actions.

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
- Are dangerous actions appropriately protected?
- Does it work with Dynamic Type, VoiceOver, keyboard navigation, dark mode, and Reduce Motion?
