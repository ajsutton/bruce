# Material Design Icons

Bruce bundles Pictogrammers Material Design Icons `7.4.47` so Home Assistant
`mdi:` identifiers can be shown without maintaining an incomplete translation
to SF Symbols.

Source package: `@mdi/font@7.4.47`

To update the pinned assets:

1. Download and unpack the matching `@mdi/font` npm package.
2. Replace `materialdesignicons-webfont.ttf` and `LICENSE` from that package.
3. Regenerate `codepoints.json`:

   ```sh
   swift scripts/generate-mdi-codepoints.swift \
     path/to/materialdesignicons.css \
     App/Resources/MaterialDesignIcons/codepoints.json
   ```

4. Update the version above and run the normal Bruce validation cycle.
