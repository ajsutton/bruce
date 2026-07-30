# Bruce Brand Guide

## Brand idea

Bruce is a native Apple-platform home app with the character of a down-to-earth Australian
who has done well for himself and now owns a very nice house.

Bruce is capable, comfortable and quietly successful. He appreciates quality but dislikes fuss.
He never talks about innovation, intelligence or automation when a plain description will do.

The core promise is:

> The house is sorted.

## Brand modes

Bruce has two complete presentation modes.

### Bruce

Bruce is the default.

- Calm, restrained and quietly premium.
- Warm render, deep pool green, eucalyptus and late-sun terracotta.
- Tailored typography with generous space.
- Plain, concise Australian English.
- Personality is expressed through understatement rather than slang.

### Full Bruce

Users may explicitly enable **Go The Full Bruce**.

- Affectionate, exaggerated and unapologetically Australian.
- Green and gold, resort-pool blue, sunburn red and Zincalume.
- Bold signwriting-inspired display typography and graphic badges.
- Larrikin language for the vast majority of user-facing copy.
- Never weakens clarity, accessibility or perceived reliability.

Full Bruce is a coordinated mode, not a collection of independent novelty settings. Enabling it
changes the app icon, decorative styling and eligible language together. Disabling it returns all
three to standard Bruce.

The preference should persist on the device. New installations and new device contexts start in
standard Bruce.

## App icon

Standard Bruce uses a warm-render field, a tailored dark-pool `B`, and one late-sun full stop.

Full Bruce uses a bottle-green field, an emphatic gold `B`, and a sunburn-red exclamation mark.
The icon may be more graphic, but its silhouette must remain readable at the smallest supported
size.

On iOS, the installed app icon follows the selected mode. On macOS, the selected mode changes the
running app's Dock icon; the Finder icon remains the standard Bruce icon because macOS does not
provide a supported persistent alternate-icon API.

Do not add a literal house, Wi-Fi arcs, circuit traces, plugs, light bulbs, Australian flags,
maps or mascots.

## Colour

### Bruce

| Token | Value | Use |
| --- | --- | --- |
| Pool deep | `#173E3B` | Primary brand field and dark surfaces |
| Eucalyptus | `#5F7862` | Supporting brand colour |
| Warm render | `#EDE3D1` | Light brand field |
| Late sun | `#D76548` | Brand accent and selected emphasis |
| Barbecue black | `#202421` | Dark neutral |

### Full Bruce

| Token | Value | Use |
| --- | --- | --- |
| Bottle green | `#00563F` | Primary brand field |
| Proper gold | `#FFCB18` | Primary Full Bruce accent |
| Resort pool | `#05A8C7` | Supporting accent |
| Sunburn | `#E84632` | Emphasis |
| Zincalume | `#D9D7CC` | Light neutral |

These are brand colours, not replacements for system semantic colours. Use platform semantic
colours for success, warning, failure, destructive actions and availability. Never communicate
state through colour alone.

## Typography

Use the system San Francisco family throughout the product.

Standard Bruce may use a restrained serif treatment in the wordmark and occasional large
editorial headings. Full Bruce may use heavier, tighter and slightly angled display treatments
in decorative brand moments.

Controls, settings, status, errors, safety information and accessibility text always use native
system typography.

## Voice

Bruce is concise, useful and comfortable with silence.

Prefer:

- `The pool’s ready.`
- `Garage is shut.`
- `Cooling downstairs now.`
- `Four lights are still on.`
- `Couldn’t reach the front door lock.`

Avoid:

- Artificial enthusiasm.
- Chatbot filler.
- Describing routine actions as smart, intelligent or magical.
- Forced slang in standard Bruce or in safety-critical Full Bruce messages.
- Calling the user `mate`, `champ` or another nickname unless a future explicit preference
  supports it.

### Full Bruce language

Full Bruce should enthusiastically use dry humour, vivid Australian phrasing and larrikin
confidence for the vast majority of user-facing language. Full Bruce is the default voice for
titles, labels, status, actions, confirmations, onboarding, settings, permissions, privacy,
account recovery, empty states, unavailable states and errors. It is allowed to be
conspicuously different from standard Bruce; a timid synonym swap is not enough.

Prefer short phrases with a strong point of view. Playful language may appear throughout, but the
phrase or its complete accessibility label and value must identify the relevant device, action
and state without relying on visual context. Icons, values and layout may reinforce the meaning.
A message being serious, technical, destructive, constrained for space or likely to require
attention is not by itself a reason to fall back to standard Bruce.

Acceptable:

- `Pool’s a ripper.`
- `Garage is shut. Good as gold.`
- `Front lock’s having a sook.`
- `Cranking the air-con downstairs.`

Humour must never delay the actual state or action.

Stale readings should retain Full Bruce language when the UI clearly identifies them as
`Last known`. The qualifier must apply to the whole group and VoiceOver value; do not phrase a
cached value as newly observed.

## Safety boundary

Safety-critical messages are the only language exception to Full Bruce. Use standard, direct
language when misunderstanding a message presents a credible risk of harm to a person or damage
to a device being controlled. In those messages, do not use humour, slang, euphemism or
brand-coloured wording.

Apply this test to the specific message and consequence, not to a broad category or screen.
Smoke, fire, gas and similar alarms will normally meet it. A control failure, ambiguous state or
confirmation meets it only when misunderstanding that particular message could cause the stated
harm. Data loss, inconvenience, privacy sensitivity, account access, an ordinary error or an
unavailable low-risk value does not meet the boundary on its own and should remain Full Bruce.

Use direct language such as:

- `Smoke detected in the kitchen.`
- `The garage door is obstructed. Keep clear.`
- `The heater did not turn off and may overheat. Turn off its power supply.`

These examples use standard language because their stated context crosses the safety boundary.
A low-risk control failure such as an unconfirmed charging-mode preference remains Full Bruce.

When a message crosses the boundary, change only the safety-critical message. Nearby headings,
navigation and unrelated supporting copy remain Full Bruce.

## Language resources

Treat Full Bruce as an Australian English language variant, not as conditional prose embedded
in views.

- Store standard Bruce as `en` and Full Bruce as `en-AU` in `App/Localizable.xcstrings`.
- Give both variants the same stable key and select the localization centrally from `BruceMode`.
- Keep domain-specific copy accessors for typed state mapping, interpolation and accessibility
  composition. They should resolve catalog keys rather than contain alternate prose.
- Do not scatter `isFullBruce` text branches through views or presentation types.
- For a safety-critical entry, put the same direct wording in both language variants. Do not
  bypass the catalog.
- Xcode may update the catalog during builds when it discovers strings in source code. Review and
  commit legitimate extracted entries and canonical reordering with the feature that caused them;
  do not leave the generated rewrite uncommitted.

Non-linguistic values such as URLs, numbers, units and an unavailable-value dash do not require
catalog entries.

### OS-owned language surfaces

Some user-facing strings are loaded by the operating system outside Bruce's process and cannot
read the stored Bruce mode or use its runtime catalog selector. This currently includes
`NSLocalNetworkUsageDescription` and the iOS `Settings.bundle`. Keep these strings plain,
concise and compatible with both modes. This is a platform boundary, not an additional reason
for in-app copy to fall back to standard Bruce. If Apple provides a mode-aware mechanism for
these surfaces, move them into the coordinated language variants.

## UI behaviour

- Bruce branding lives in app icons, voice, selection, empty states and a small number of
  high-impact moments.
- Native controls, navigation and materials remain native in both modes.
- Mode changes must not rearrange controls, alter accessibility identifiers or change the
  meaning of an action.
- Full Bruce decoration must respect Reduce Motion, Increase Contrast and Dynamic Type.
- Full Bruce decoration needs a restrained fallback for constrained contexts such as
  complications, notifications and CarPlay. The language remains Full Bruce unless the specific
  message crosses the safety boundary.

## Privacy

The public brand must never reference the family name, street address, suburb, identifiable
property photography or other location-derived details.

The house may inspire abstract colour, material, geometry and atmosphere only.
