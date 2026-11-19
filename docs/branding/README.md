# Bruce artwork

## Current icons

- Standard Bruce: the approved Practical Butler cream bush-hat-and-bow-tie mark on green.
  `bruce-portrait.png` is the canonical 1024 × 1024 opaque RGB source. The mark was
  extracted from the top-left concept in the AI-generated design sheet and flattened
  onto a square green field, excluding the presentation label and pre-rounded mask.
- Full Bruce: the approved golden beer mug with cream foam on eucalyptus green.
  `bruce-full-beer.png` is the canonical 1024 × 1024 opaque RGB source, resized from
  the approved 1254 × 1254 AI-generated beer artwork. No hat, face or lightning bolt.
- Source filenames are retained for generator compatibility; they no longer depict portraits.
- iOS and CarPlay: opaque square artwork; the system applies the final mask.
- macOS: rounded artwork inset by 10%, with transparent outer padding.
- Neither source contains household photographs or identifying property details.

## Regeneration

Regenerate every asset on macOS from the repository root:

```sh
swift scripts/generate-brand-icons.swift
```

`--carplay-only` regenerates only the existing CarPlay sizes. No asset names,
catalogue slots, runtime selection logic or app functionality change.

The [contact sheet](icon-preview.png) shows the committed iOS and Mac variants at
large and small sizes. These assets were rendered with Pillow using the same
10% Mac inset and 22%-of-tile corner radius as the AppKit generator. Regenerated
PNG bytes may differ by renderer; dimensions, opacity, artwork framing and
variant treatment should remain consistent. iOS sources have no pre-rounded
corners or transparent padding.

The existing Full Bruce preference continues to select the alternate iOS icon
and running Mac Dock icon. The Finder icon remains standard Bruce.
