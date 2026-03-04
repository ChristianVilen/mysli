# Distribution — Ku-Ka

## Overview

Ku-Ka is distributed outside the App Store via Developer ID notarization. This is required because the app uses `CGEvent` taps (Accessibility) and `CGWindowListCreateImage` (Screen Recording), which are incompatible with App Sandbox.

🌐 **Website**: [https://christianvilen.github.io/ku-ka](https://christianvilen.github.io/ku-ka)

## Prerequisites

- [ ] Apple Developer Program membership ($99/year)
- [ ] App builds and runs correctly on macOS 13+

## Step 1: Signing Setup

- [ ] Set a unique `PRODUCT_BUNDLE_IDENTIFIER` (e.g., `com.yourname.kuka`)
- [ ] Select a Development Team in Xcode → Signing & Capabilities
- [ ] Signing Certificate: **Developer ID Application**
- [ ] Add an App Icon to the asset catalog

## Step 2: Archive & Notarize

1. In Xcode, set scheme destination to **Any Mac (Apple Silicon, Intel)**
2. **Product → Archive**
3. In Organizer, select the archive → **Distribute App**
4. Choose **Developer ID** → **Upload** (sends to Apple for notarization)
5. Wait for notarization (usually a few minutes)
6. **Export Notarized App**

## Step 3: Create a DMG

```bash
# Create a folder with the app and an Applications symlink
mkdir -p dmg-staging
cp -R /path/to/KuKa.app dmg-staging/
ln -s /Applications dmg-staging/Applications

# Create the DMG
hdiutil create -volname "Ku-Ka" -srcfolder dmg-staging -ov -format UDZO KuKa.dmg
rm -rf dmg-staging
```

Users install by opening the DMG and dragging Ku-Ka to Applications.

## Step 4: Distribute

Options for hosting:
- **GitHub Releases** — attach the DMG to a tagged release
- **Personal website** — direct download link
- **Gumroad / Itch.io** — if you want to charge for it

## Checklist

| Step | Status |
|------|--------|
| Apple Developer membership | ⬜ |
| Developer ID signing | ⬜ |
| App icon | ⬜ |
| Archive & notarize | ⬜ |
| Create DMG | ⬜ |
| Host for download | ⬜ |
