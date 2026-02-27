# Sunarira faithful assets (no code integration yet)

This folder contains implementation-ready image assets generated from the provided sketch/reference style.

## App icon assets

- `Sunarira-AppIcon-1024.png`
  - Master app icon (1024x1024).
- `Sunarira-Glyph-1024.png`
  - Transparent glyph-only variant.
- `Sunarira.iconset/`
  - macOS iconset PNG files:
    - `icon_16x16.png`
    - `icon_16x16@2x.png`
    - `icon_32x32.png`
    - `icon_32x32@2x.png`
    - `icon_128x128.png`
    - `icon_128x128@2x.png`
    - `icon_256x256.png`
    - `icon_256x256@2x.png`
    - `icon_512x512.png`
    - `icon_512x512@2x.png`

## Menu bar assets

Files are prepared for idle and transforming states in both template and color variants.

- `menubar/menubar-idle-template-20.png`
- `menubar/menubar-idle-template-40.png`
- `menubar/menubar-busy-template-20.png`
- `menubar/menubar-busy-template-40.png`
- `menubar/menubar-idle-color-20.png`
- `menubar/menubar-idle-color-40.png`
- `menubar/menubar-busy-color-20.png`
- `menubar/menubar-busy-color-40.png`

## Preview

- `preview/sunarira-faithful-assets-preview.png`
  - Quick visual check board of the generated assets.

## Notes

- No source code was changed.
- `iconutil` failed in this environment with `Invalid Iconset`, so `.icns` was not generated here.
- The iconset PNG files are ready for Xcode asset import as-is.
