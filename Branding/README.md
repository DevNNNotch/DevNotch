# DevNotch Brand Assets

`devnotch-app-icon.svg` is the editable source for the DevNotch application icon. It combines a physical notch, a terminal prompt, and a progress line without embedding text.

Regenerate every macOS asset-catalog size with:

```sh
scripts/generate-app-icon
```

The script uses macOS Quick Look and `sips`, validates the source path, and fails when rendering does not produce an image. Generated PNG files are committed so Xcode and GitHub can render the project without running the script.
