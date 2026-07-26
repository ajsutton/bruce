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
- More larrikin language for safe, routine household information.
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
- Performing Australianness in every sentence.
- Calling the user `mate`, `champ` or another nickname unless a future explicit preference
  supports it.

### Full Bruce language

Full Bruce may add dry humour or familiar Australian phrasing to routine, reversible and
low-stakes information.

Acceptable:

- `Pool’s a ripper.`
- `Garage is shut. Good as gold.`
- `Front lock’s having a sook.`
- `Cranking the air-con downstairs.`

Humour must never delay the actual state or action.

## Safety boundary

The following language never changes between modes:

- Smoke, fire, gas, water-leak and security alarms.
- Lock or access ambiguity.
- Destructive confirmations.
- Unavailable, stale or unverified state.
- Errors where misunderstanding could cause harm or damage.
- Permissions, privacy and account recovery.

Use direct language such as:

- `Smoke detected in the kitchen.`
- `The front door may be unlocked. Current state is unavailable.`
- `The garage did not close.`

## UI behaviour

- Bruce branding lives in app icons, voice, selection, empty states and a small number of
  high-impact moments.
- Native controls, navigation and materials remain native in both modes.
- Mode changes must not rearrange controls, alter accessibility identifiers or change the
  meaning of an action.
- Full Bruce decoration must respect Reduce Motion, Increase Contrast and Dynamic Type.
- Every Full Bruce treatment needs a restrained fallback for constrained contexts such as
  complications, notifications and CarPlay.

## Privacy

The public brand must never reference the family name, street address, suburb, identifiable
property photography or other location-derived details.

The house may inspire abstract colour, material, geometry and atmosphere only.
