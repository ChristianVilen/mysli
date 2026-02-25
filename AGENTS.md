# Selected Area Screen Capture (app name Ku-Ka (kuvakaappaus))

## Overview

A lightweight macOS app to replace the default `Shift+Command+4` selected area screenshot functionality. The app will:

- Capture a user-selected area of the screen.
- Multi-monitor support — dims all screens, captures from the screen where the cursor is.
- Save the screenshot to `~/Screenshots/`.
- Copy the screenshot to the clipboard.
- Floating thumbnail preview after capture — click to annotate with freehand drawing.

---

## Architecture

### File Structure

```
KuKa/
├── main.swift           # App entry point (NSApplication.shared.run())
├── AppDelegate.swift    # NSStatusItem menu bar, wires hotkey → overlay → capture → thumbnail → editor pipeline
├── HotkeyManager.swift  # CGEvent tap intercepting Shift+Command+4 globally
├── OverlayWindow.swift  # Borderless transparent NSWindow at screenSaver level
├── SelectionView.swift  # NSView handling mouseDown/Dragged/Up, draws dimmed overlay + selection rect + dimensions
├── CaptureManager.swift # CGWindowListCreateImage capture, PNG save, clipboard copy, sound + notification
├── ThumbnailPanel.swift # Floating preview panel in bottom-right corner after capture
├── DrawingView.swift    # NSView for freehand red drawing on screenshot image
├── EditorWindow.swift   # Centered modal window for annotating screenshots
├── Info.plist           # LSUIElement=true, NSScreenCaptureUsageDescription
└── KuKa.entitlements    # Sandbox disabled (required for CGEvent tap + screen capture)
```

### Key Classes

| Class | Responsibility |
|-------|---------------|
| `AppDelegate` | Menu bar icon, launch-at-login toggle, orchestrates the capture flow, multi-monitor overlay management |
| `HotkeyManager` | `CGEvent.tapCreate` to intercept `Shift+Command+4`, fires callback |
| `OverlayWindow` | Full-screen borderless `NSWindow` covering each display |
| `SelectionView` | Mouse drag selection, dimmed background, real-time dimensions label |
| `CaptureManager` | `CGWindowListCreateImage`, PNG save to `~/Screenshots/`, clipboard, shutter sound, `UNUserNotificationCenter` |
| `ThumbnailPanel` | Floating preview in bottom-right corner, 5s auto-dismiss, click to open editor |
| `DrawingView` | Freehand red drawing on screenshot, undo support, composites final image |
| `EditorWindow` | Centered modal for annotation with Undo and Done buttons |

### Flow

```
Shift+Cmd+4 → HotkeyManager (suppresses event) → AppDelegate.startCapture()
→ OverlayWindows shown on all screens → User drags selection on cursor's screen
→ SelectionView reports CGRect → All overlays dismissed → 50ms delay
→ CaptureManager.capture(rect, screen) → Save PNG + Copy clipboard + Shutter sound + Notification
→ ThumbnailPanel shown (bottom-right, 5s timeout) → Click thumbnail → EditorWindow opens
→ Freehand drawing → Done → Overwrite PNG + Update clipboard
```

---

## Requirements

### Functional Requirements

1. **Selected Area Capture** — Triggered by `Shift+Command+4`, user selects rectangular area with visual feedback (crosshair, dimensions).
2. **Save to Screenshots Folder** — PNG saved to `~/Screenshots/` as `Screenshot_YYYY-MM-DD_at_HH-MM-SS.png`.
3. **Copy to Clipboard** — Captured image automatically copied to clipboard.
4. **User Experience** — No persistent window, menu bar agent only. Shutter sound + system notification on capture.

### Technical Requirements

- **Language**: Swift 5, macOS 13.0+
- **Frameworks**: AppKit, CoreGraphics, ServiceManagement, UserNotifications
- **Permissions**: Accessibility (CGEvent tap), Screen Recording (CGWindowListCreateImage)
- **Launch at Login**: `SMAppService.mainApp.register()` / `unregister()`

---

## Implementation Notes

### Keyboard Shortcut
- Uses `CGEvent.tapCreate` at `.cgSessionEventTap` to intercept key-down events globally.
- Filters for keyCode `0x15` (4 key) with `.maskShift` + `.maskCommand`.
- Returns `nil` to suppress the system screenshot tool.
- Requires Accessibility permission; prompts user if missing.

### Screen Capture
- Overlay window is dismissed before capture to exclude it from the screenshot.
- 50ms delay after dismissal ensures the overlay is fully gone.
- `CGWindowListCreateImage` with `.optionOnScreenOnly` and `.bestResolution`.
- Coordinate conversion from NSView (bottom-left origin) to CGDisplay (top-left origin).

### Selection Overlay
- `OverlayWindow` at `.screenSaver` level, borderless, transparent.
- `SelectionView` draws dimmed background (30% black), clears selected rect, white border, monospaced dimensions label.
- Escape key cancels selection.
- Zero-size selections are ignored.
