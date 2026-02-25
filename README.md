# Ku-Ka (kuvakaappaus)

A lightweight macOS menu bar app that replaces the default `Shift+Command+4` screenshot functionality. Select an area, save it as PNG, and copy it to your clipboard — all in one step.

## Features

- Intercepts `Shift+Command+4` globally to replace the system screenshot tool
- Multi-monitor support — dims all screens, captures from the screen where the cursor is
- macOS-style selection overlay with dimmed background and real-time dimensions display
- Saves screenshots as PNG to `~/Screenshots/`
- Automatically copies the screenshot to the clipboard
- Shutter sound + system notification on capture
- Floating thumbnail preview after capture — click to annotate with freehand drawing
- Launch at Login toggle
- Runs as a menu bar agent (no Dock icon)

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15+ (to build)

## Build & Run

1. Open `KuKa.xcodeproj` in Xcode
2. Select the `KuKa` scheme and your Mac as the destination
3. `Cmd+R` to build and run

## Permissions

On first launch, Ku-Ka needs two permissions:

### Accessibility (required)
The app intercepts `Shift+Command+4` via a `CGEvent` tap, which requires Accessibility access.

**System Settings → Privacy & Security → Accessibility** → Enable Ku-Ka

If permission is missing, the app will show an alert and offer to open System Settings for you.

### Screen Recording (required)
`CGWindowListCreateImage` requires screen recording permission to capture screen content.

**System Settings → Privacy & Security → Screen Recording** → Enable Ku-Ka

macOS will prompt you automatically on the first capture attempt.

## Usage

1. Launch Ku-Ka — it appears as a camera icon in the menu bar
2. Press `Shift+Command+4` anywhere
3. Click and drag to select the area you want to capture
4. Release the mouse — the screenshot is saved and copied
5. A thumbnail preview appears in the bottom-right corner for 5 seconds
6. Click the thumbnail to open the annotation editor — draw on the screenshot with freehand red lines
7. Click **Done** to save the annotated version (overwrites the file and updates the clipboard)
8. Press `Escape` to cancel a selection

## Screenshots Location

Screenshots are saved to `~/Screenshots/` with the naming convention:

```
Screenshot_2026-02-23_at_14-30-00.png
```

The folder is created automatically if it doesn't exist.

## Menu Bar Options

- **Launch at Login** — Toggle to start Ku-Ka automatically when you log in
- **Quit Ku-Ka** — Exit the app

## File Structure

```
KuKa/
├── main.swift           # App entry point
├── AppDelegate.swift    # Menu bar setup, wires hotkey → overlay → capture → thumbnail → editor
├── HotkeyManager.swift  # CGEvent tap for Shift+Command+4 interception
├── OverlayWindow.swift  # Full-screen transparent overlay window
├── SelectionView.swift  # Mouse drag selection with dimmed background + dimensions
├── CaptureManager.swift # Screen capture, save to disk, clipboard, notifications
├── ThumbnailPanel.swift # Floating preview panel after capture
├── DrawingView.swift    # Freehand red drawing on screenshot image
├── EditorWindow.swift   # Centered modal for annotating screenshots
├── Info.plist           # App config (LSUIElement, screen capture usage)
└── KuKa.entitlements    # Entitlements (sandbox disabled)
```

## Known Limitations

- You must disable or accept that the system `Shift+Command+4` is intercepted (the app suppresses the system shortcut when running)
- Requires macOS 13+ for `SMAppService` (launch at login)
- No preferences UI for changing the shortcut key (hardcoded to `Shift+Command+4`)
