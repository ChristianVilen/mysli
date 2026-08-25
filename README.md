# Ku-Ka (kuvakaappaus)

A lightweight macOS menu bar app that replaces the default `Shift+Command+4` screenshot functionality. Select an area, save it as PNG, and copy it to your clipboard — all in one step.

🌐 **Website**: [https://christianvilen.github.io/ku-ka](https://christianvilen.github.io/ku-ka)

## Features

- Intercepts `Shift+Command+3` and `Shift+Command+4` globally to replace the system screenshot tools
- Full screen capture with `Shift+Command+3` — captures the screen where the cursor is, with flash animation
- Multi-monitor support — dims all screens, captures from the screen where the cursor is
- macOS-style selection overlay with dimmed background and real-time dimensions display
- Saves screenshots as PNG to `~/Screenshots/`
- Automatically copies the screenshot to the clipboard
- Floating thumbnail preview after capture — click to annotate with freehand drawing or crop
- Delete screenshots from thumbnail or editor — removes file and clears clipboard
- Launch at Login toggle
- Keep Awake — stop the Mac from sleeping while a long task (such as an AI coding agent) runs, with a menu-bar toggle and timed sessions
- Window tiling — hotkeys to snap the active window to the left half, right half, or full screen of its display
- Runs as a menu bar agent (no Dock icon)

## Keep Awake

Pick **Keep Awake For** a preset (30 minutes, 1, 2, or 4 hours, or "Until I turn it off") from the menu bar and Ku-Ka will keep your Mac from going to sleep while it's working through something long, like an overnight agent run. The menu-bar icon is tinted while it's on, and the menu shows how much time is left.

It stops the system from sleeping but still lets the display turn off, so you're not burning the screen for nothing. One caveat: closing a laptop's lid still sleeps the Mac unless it's plugged in with an external display attached — no app can get around that. Keep the lid open or run it docked.

## Window Tiling

Three hotkeys move the active window around its display:

- `Ctrl+Option+Left Arrow` — snap the window to the left half of the screen
- `Ctrl+Option+Right Arrow` — snap the window to the right half of the screen
- `Ctrl+Option+Return` — maximize the window; press it again to put the window back where it was before

If you use Stage Manager (the macOS feature that shows recent apps as small thumbnails down the side of the screen), maximize leaves room for its strip on the left, plus a small gap at the top, bottom, and right. This only happens when Stage Manager is turned on **and** there are two or more windows visible on that screen — with just one window, or with Stage Manager off, maximize fills the whole screen. Left- and right-half tiling never leaves this gap, so a half-tiled window can sit under the Stage Manager strip.

With more than one display, the window is tiled on the screen it overlaps the most. This differs from the screenshot features, which follow the cursor.

The whole feature can be turned on and off with the **Window Tiling** checkbox in the menu bar menu (under Settings); the choice is remembered across restarts. While it's off, the hotkeys pass through to other apps. The keys themselves aren't configurable.

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15+ (to build)

## Installation

### Homebrew (Recommended)

```bash
# Tap the repository
brew tap ChristianVilen/ku-ka

# Install the app
brew install --cask kuka
```

**Important**: Since this is an unsigned app from an untrusted developer, you'll need to trust it:

```bash
# Remove the quarantine attribute (replace with actual path if different)
sudo xattr -d com.apple.quarantine /Applications/Ku-Ka.app
```

Alternatively, you can use the GUI method:
1. Try to open Ku-Ka from Applications
2. When blocked, go to **System Settings → Privacy & Security**
3. Click **"Open Anyway"** next to the Ku-Ka warning

### Manual Installation

1. Download the latest `.zip` from [GitHub Releases](https://github.com/ChristianVilen/ku-ka/releases/latest)
2. Unzip and move Ku-Ka.app to your Applications folder
3. Run the same trust command above

## Build & Run

1. Open `KuKa.xcodeproj` in Xcode
2. Select the `KuKa` scheme and your Mac as the destination
3. `Cmd+R` to build and run

## Permissions

Ku-Ka needs two permissions. On first launch (and whenever one is missing) a setup window opens — a short welcome page, then one row per permission with a Grant button and a live ❌/✅ status. Grant each one in System Settings and the row flips to ✅ by itself, no relaunch needed. The window can be reopened anytime from the menu bar via **Permissions…**, and the menu-bar icon shows a small orange dot while a permission is missing.

### Accessibility (required)
The app intercepts `Shift+Command+3/4` via a `CGEvent` tap, which requires Accessibility access. The same permission also lets Ku-Ka move and resize windows, which is what the window tiling hotkeys use — no separate permission is needed for that.

**System Settings → Privacy & Security → Accessibility** → Enable Ku-Ka

The hotkeys start working the moment the permission is granted.

### Screen Recording (required)
ScreenCaptureKit requires screen recording permission to capture screen content.

**System Settings → Privacy & Security → Screen Recording** → Enable Ku-Ka

Two macOS quirks to expect: the first capture can require one quit-and-reopen of Ku-Ka before the grant takes effect, and roughly every month macOS makes every screenshot app ask again for screen recording. Neither is something Ku-Ka can turn off.

## Usage

1. Launch Ku-Ka — it appears as a camera icon in the menu bar
2. Press `Shift+Command+3` to capture the full screen (the screen where your cursor is) — a flash animation confirms the capture
3. Press `Shift+Command+4` anywhere
3. Click and drag to select the area you want to capture
4. Release the mouse — the screenshot is saved and copied
5. A thumbnail preview appears in the bottom-right corner for 5 seconds
6. Click the thumbnail to open the editor — draw on the screenshot with freehand red lines, or press **Crop** and drag a box over the part you want to keep (drag the handles to resize, drag inside to move, click outside to remove the box)
7. Click **Done** to save the edited version (overwrites the file and updates the clipboard)
8. Click the **trash icon** on a thumbnail or **Delete** in the editor to delete the screenshot file and clear the clipboard
9. Press `Escape` to cancel a selection

## Screenshots Location

Screenshots are saved to `~/Screenshots/` with the naming convention:

```
Screenshot_2026-02-23_at_14-30-00.png
```

The folder is created automatically if it doesn't exist.

## Menu Bar Options

- **Launch at Login** — Toggle to start Ku-Ka automatically when you log in
- **Window Tiling** — Turn the tiling hotkeys on or off (remembered across restarts)
- **Thumbnail Duration** — Choose how long the floating thumbnail stays visible: 3 Seconds, 5 Seconds, or Forever (until dismissed)
- **Keep Awake** — Keep the Mac from sleeping for a preset time (30 minutes, 1, 2, or 4 hours, or until turned off), with a "Keep display awake" checkbox
- **Quit Ku-Ka** — Exit the app

## File Structure

```
KuKa/
├── main.swift           # App entry point
├── AppDelegate.swift    # Menu bar setup, wires hotkey → overlay → capture → thumbnail → editor
├── HotkeyManager.swift  # CGEvent tap for Shift+Command+4 interception
├── OverlayWindow.swift  # Full-screen transparent overlay window
├── SelectionView.swift  # Mouse drag selection with dimmed background + dimensions
├── CaptureManager.swift # Screen capture, save to disk, clipboard, delete
├── FlashView.swift      # White flash animation on screen after full-screen capture
├── ThumbnailPanel.swift # Floating preview panel after capture (with delete)
├── ThumbnailStackManager.swift # Manages stacking of multiple thumbnail panels
├── CombineButton.swift  # Floating "Combine" button between adjacent thumbnails
├── DrawingView.swift    # Freehand red drawing on screenshot image
├── EditorWindow.swift   # Centered modal for annotating screenshots
├── WindowTilingController.swift # Ties tiling hotkeys to the layout engine and window control
├── TilingLayoutEngine.swift  # Pure layout math for left/right/maximize tiling
├── TilingScreenRules.swift # Screen-picking + windows-per-screen counting, for the Stage Manager check
├── StageManagerDetector.swift # Reads whether Stage Manager is turned on
├── AccessibilityWindowControl.swift # Reads/moves the focused window via the Accessibility API
├── WindowListProvider.swift  # Lists on-screen windows via the window server
├── ScreenCoordinates.swift   # Shared top-left/bottom-left coordinate flip
├── Info.plist           # App config (LSUIElement, screen capture usage)
└── KuKa.entitlements    # Entitlements (sandbox disabled)
```

## Known Limitations

- You must disable or accept that the system `Shift+Command+3` and `Shift+Command+4` are intercepted (the app suppresses the system shortcuts when running)
- `Ctrl+Option+Left/Right/Return` are intercepted globally while window tiling is enabled, even inside apps that use those same keys for something else. Turn off **Window Tiling** in the menu to give the keys back to other apps.
- Requires macOS 14+ for ScreenCaptureKit screenshot capture
- No preferences UI for changing the shortcut keys, including the window tiling hotkeys
- Some windows can't be tiled — apps that don't let their windows be moved or resized through the Accessibility API, and Ku-Ka's own windows. The hotkey then does nothing; there is no error message.

## Testing

### Running Tests

- **Xcode**: `Cmd+U` runs both unit and UI test suites
- **CLI**: `xcodebuild -project KuKa.xcodeproj -scheme KuKa test`

### Unit Tests (KuKaTests)

`CaptureManager` uses protocol-based dependency injection (`FileManaging`, `ClipboardManaging`, `ScreenCapturing`) so all external dependencies are mocked in tests — no real disk writes, clipboard access, or screen capture needed.

Tests cover:
- Capture success/failure paths
- File saving and clipboard operations
- Coordinate conversion (NSView → CGDisplay)
- Screenshot file naming format
- Annotated image save
- Crop box geometry (draw, move, resize, flip, clear) and the crop's pixel mapping
- Screenshot deletion (file removal + clipboard clear)
- Tiling layout math and the maximize/restore toggle, including apps that snap window sizes
- Screen-picking and windows-per-screen rules, plus the tiling controller's saved-frame handling
- Hotkey routing: tiling keys are swallowed while enabled and pass through while disabled; screenshot keys work either way

### UI Tests (KuKaUITests)

XCUITest suite verifying menu bar interactions:
- Status item exists
- Menu contains all expected items (Launch at Login, Thumbnail Duration options, Quit)
- Duration selection persists across menu re-open

### Test-Mode Guard

When running under XCTest, the app skips hotkey registration to avoid permission prompts. Detection uses `XCTestConfigurationFilePath` (unit tests) and `--uitesting` launch argument (UI tests).
