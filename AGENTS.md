# Selected Area Screen Capture (app name Ku-Ka (kuvakaappaus))

## Overview

A lightweight macOS app to replace the default `Shift+Command+4` selected area screenshot functionality. The app will:

- Capture a user-selected area of the screen.
- Capture the full screen instantly with `Shift+Command+3` (captures the screen where the cursor is, with flash animation).
- Multi-monitor support — dims all screens, captures from the screen where the cursor is.
- Save the screenshot to `~/Screenshots/`.
- Copy the screenshot to the clipboard.
- Floating thumbnail preview after capture — click to annotate with freehand drawing.
- Delete screenshots from thumbnail or editor — removes file and clears clipboard.
- Keep Awake — prevent the Mac from idle-sleeping from the menu bar, for a preset time (30m/1h/2h/4h) or until turned off, with an optional "keep display awake" preference.
- Window tiling — `Ctrl+Option+Left/Right/Return` snaps the active window to the left half, right half, or full screen of its display (maximize toggles back to the previous frame). Stage Manager-aware, with a menu toggle to turn the hotkeys off.

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
├── CaptureManager.swift # CGWindowListCreateImage capture, PNG save, clipboard copy
├── FlashView.swift      # White flash animation on screen after full-screen capture
├── ThumbnailPanel.swift # Floating preview panel in bottom-right corner after capture
├── ThumbnailStackManager.swift # Manages stacking of multiple thumbnail panels
├── FloatingPanel.swift  # Base class for borderless floating panels (thumbnails, combine button)
├── CombineButton.swift  # Floating "Combine" button between adjacent thumbnails
├── DrawingView.swift    # NSView for freehand red drawing on screenshot image
├── EditorWindow.swift   # Centered modal window for annotating screenshots
├── WindowListProvider.swift  # CGWindowListCopyWindowInfo wrapper: layer-0 on-screen windows, NS-space coordinates
├── WakeSession.swift    # Pure model of a keep-awake session (duration, expiry)
├── WakeManager.swift    # Keep-awake orchestration + IOKit power assertion seam
├── KeepAwakeController.swift # Keep Awake menu section: state, countdown, persistence, notification
├── KeepAwakePanelView.swift # Inline menu panel: duration chips + display-awake checkbox
├── WindowTilingController.swift # @MainActor: ties tiling hotkeys to TilingLayoutEngine and AccessibilityWindowControl
├── TilingLayoutEngine.swift  # Pure layout math: target frame + move/restore decision for left/right/maximize
├── TilingScreenRules.swift # Screen-picking + windows-per-screen counting (for the Stage Manager check)
├── StageManagerDetector.swift # Reads the system Stage Manager on/off setting, fresh on every access
├── AccessibilityWindowControl.swift # AX-API glue: reads/moves the focused window, NS-space coordinates
├── ScreenCoordinates.swift   # Shared top-left (CG/AX) <-> bottom-left (NS) coordinate flip
├── Info.plist           # LSUIElement=true, NSScreenCaptureUsageDescription
└── KuKa.entitlements    # Sandbox disabled (required for CGEvent tap + screen capture)
```

### Key Classes

| Class | Responsibility |
|-------|---------------|
| `AppDelegate` | Menu bar icon, launch-at-login toggle, Window Tiling toggle (persisted as `windowTilingEnabled`), thumbnail duration setting, orchestrates the capture flow, multi-monitor overlay management |
| `HotkeyManager` | `CGEvent.tapCreate` to intercept the screenshot combos (`Shift+Command+3/4`) and, while tiling is enabled, the tiling combos (`Ctrl+Option+Left/Right/Return`); routes everything through a single `onAction` callback with the `HotkeyAction` enum |
| `OverlayWindow` | Full-screen borderless `NSWindow` covering each display |
| `SelectionView` | Mouse drag selection, dimmed background, real-time dimensions label |
| `CaptureManager` | Protocol-based DI (`FileManaging`, `ClipboardManaging`, `ScreenCapturing`), PNG save to `~/Screenshots/`, clipboard copy, screenshot deletion |
| `FlashView` | White flash animation overlay on screen after full-screen capture |
| `ThumbnailPanel` | Floating preview in bottom-right corner, configurable auto-dismiss (3s/5s/forever), click to open editor, delete button to remove screenshot |
| `ThumbnailStackManager` | Manages multiple thumbnail panels: stacking (max 5), positioning, timer logic (solo=timed, multi=persist), animated repositioning on dismiss |
| `CombineButton` | Floating "Combine" button with liquid glass visual, appears between adjacent thumbnails for merging two screenshots into one |
| `DrawingView` | Freehand red drawing on screenshot, undo support, composites final image |
| `EditorWindow` | Centered modal for annotation with Undo, Delete, and Done buttons |
| `WakeSession` | Pure, side-effect-free session model; all time queries take an explicit `now` |
| `WakeManager` | Drives the `SleepPreventing` seam (IOKit power assertion), expiry timer, `keepDisplayAwake` mode |
| `KeepAwakeController` | Keep Awake AppKit glue: builds the menu section, per-second countdown, persists the display preference, expiry notification |
| `KeepAwakePanelView` | Custom `NSView` menu item: status line, duration chips (segmented control), "Keep display awake" checkbox |
| `WindowTilingController` | `@MainActor`, thin orchestrator: reads the focused window, picks its screen, asks `TilingLayoutEngine` what to do, carries it out through `WindowControlling`; owns the pre-maximize saved-frame map |
| `TilingLayoutEngine` | Pure, stateless layout math: target frame for left-half/right-half/maximize, and whether a maximize should move the window or restore its pre-maximize frame |
| `TilingScreenRules` | Two screen-related rules: counts how many on-screen windows "belong" to a given screen (for the Stage Manager strip check), and picks which screen a window should be tiled against |
| `StageManagerDetector` | Reads whether Stage Manager is turned on, fresh on every access (no caching, since the user can toggle it any time) |
| `AccessibilityWindowControl` | Accessibility-API glue: reads the focused window's frame and moves/resizes it; converts between AX (top-left origin) and NS (bottom-left origin) coordinates |
| `WindowListProvider` | Lists on-screen, layer-0 windows (excluding Ku-Ka's own) via `CGWindowListCopyWindowInfo`, converted to NS coordinates |
| `ScreenCoordinates` | Shared vertical-flip math used by both `WindowListProvider` and `AccessibilityWindowControl` for CG/AX ↔ NS coordinate conversion |

### Flow

```
Shift+Cmd+3 → HotkeyManager (suppresses event) → AppDelegate.startFullScreenCapture()
→ Detect cursor screen → CaptureManager.captureFullScreen(screen) → Save PNG + Copy clipboard
→ FlashView.flash(on: screen) → ThumbnailPanel shown (bottom-right)

Shift+Cmd+4 → HotkeyManager (suppresses event) → AppDelegate.startCapture()
→ OverlayWindows shown on all screens → User drags selection on cursor's screen
→ SelectionView reports CGRect → All overlays dismissed → 50ms delay
→ CaptureManager.capture(rect, screen) → Save PNG + Copy clipboard
→ ThumbnailPanel shown (bottom-right, 5s timeout) → Click thumbnail → EditorWindow opens
→ Freehand drawing → Done → Overwrite PNG + Update clipboard

Ctrl+Opt+Left/Right/Return → HotkeyManager (suppresses event; skipped entirely when the
"Window Tiling" menu toggle is off — keys pass through) → WindowTilingController.tile(action)
→ TilingLayoutEngine.resolve(action, ...) decides move-and-save or restore
→ AccessibilityWindowControl.setFrame(...) moves the window
```

---

## Requirements

### Functional Requirements

1. **Selected Area Capture** — Triggered by `Shift+Command+4`, user selects rectangular area with visual feedback (crosshair, dimensions).
2. **Full Screen Capture** — Triggered by `Shift+Command+3`, instantly captures the screen where the cursor is with a flash animation.
2. **Save to Screenshots Folder** — PNG saved to `~/Screenshots/` as `Screenshot_YYYY-MM-DD_at_HH-MM-SS.png`.
3. **Copy to Clipboard** — Captured image automatically copied to clipboard.
4. **User Experience** — No persistent window, menu bar agent only. Floating thumbnail preview after capture.

### Technical Requirements

- **Language**: Swift 5, macOS 14.0+
- **Frameworks**: AppKit, CoreGraphics, ScreenCaptureKit, ServiceManagement, ApplicationServices (Accessibility API for window tiling)
- **Permissions**: Accessibility (covers both the CGEvent tap and AX window move/resize — no extra grant for tiling), Screen Recording (ScreenCaptureKit)
- **Launch at Login**: `SMAppService.mainApp.register()` / `unregister()`
- **Build flag**: the KuKa app target sets `OTHER_SWIFT_FLAGS = "-enable-upcoming-feature IsolatedDefaultValues"`. This exists because `WindowTilingController`'s init has default argument values (`AccessibilityWindowControl()`, etc.) that construct `@MainActor` types, and under Swift 5 language mode the compiler otherwise treats those defaults as evaluated outside the actor. The flag becomes redundant once the project moves to Swift 6 language mode, where this is the default behavior.

---

## Future Features

- **Window Capture** (`Shift+Cmd+4` then `Space`) — click a window to capture just that window
- **Screen Recording** — capture video of a selected area or full screen

---

## Implementation Notes

### Keyboard Shortcut
- Uses `CGEvent.tapCreate` at `.cgSessionEventTap` to intercept key-down events globally.
- Screenshot combos: keyCode `0x14` (3 key) and `0x15` (4 key) with `.maskShift` + `.maskCommand`.
- Tiling combos: keyCode `0x7B` (Left), `0x7C` (Right), `0x24` (Return) with `.maskControl` + `.maskAlternate`. Command and Shift must be absent so these can't collide with the screenshot combos. Arrow keys carry extra flags (`.maskSecondaryFn`, `.maskNumericPad`), so the check is "required flags present, forbidden flags absent" rather than an exact match.
- All matches route through one `onAction` closure with the `HotkeyAction` enum (`.captureArea`, `.captureFullScreen`, `.tile(TilingAction)`).
- The `tilingEnabled` flag gates the tiling combos: while off they are not matched at all and pass through to other apps. Screenshot combos are unaffected by the flag.
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

---

## Testing

### Architecture

`CaptureManager` uses protocol-based dependency injection for testability:

| Protocol | Real Implementation | Responsibility |
|----------|-------------------|----------------|
| `FileManaging` | `FileManager` | Directory creation, file writing, file deletion |
| `ClipboardManaging` | `SystemClipboard` | Pasteboard operations, clipboard clearing |
| `ScreenCapturing` | `SystemScreenCapture` | `CGWindowListCreateImage` wrapper |

### Test Targets

```
KuKaTests/                    # Unit tests (XCTest, macOS 14.0+)
├── CaptureManagerTests.swift # Tests for capture, save, clipboard, coordinate conversion, file naming
├── DrawingViewTests.swift    # Tests for freehand drawing and image compositing
├── ThumbnailStackManagerTests.swift # Tests for thumbnail stacking and timer logic
├── WindowListProviderTests.swift # Tests for window enumeration
├── WakeSessionTests.swift    # Tests for the pure keep-awake session model
├── WakeManagerTests.swift    # Tests for keep-awake orchestration against a fake preventer
├── KeepAwakeControllerTests.swift # Tests for the Keep Awake menu section and persistence
├── TilingLayoutEngineTests.swift # Target frame math and move/restore decisions for left/right/maximize
├── TilingAdaptersTests.swift # TilingScreenRules screen-membership + screen-picking rules, AX/NS coordinate conversion
├── WindowTilingControllerTests.swift # Saved-frame map behavior: save-then-restore, failed moves, entry lifecycle
├── HotkeyManagerTests.swift  # Event routing: tiling combos swallowed/passed through per the tilingEnabled flag, screenshot combos always work
└── Mocks.swift               # MockFileManager, MockClipboard, MockScreenCapture, MockWindowListProvider, MockWindowControlling, MockStageManagerDetecting, FakeSleepPreventer

KuKaUITests/                  # UI tests (XCUITest, macOS 14.0+)
└── MenuBarTests.swift        # Menu bar icon, menu items, thumbnail duration selection
```

### Test-Mode Guard

When running under XCTest, `AppDelegate` skips hotkey registration and notification authorization to avoid permission prompts:
- Unit tests: detected via `XCTestConfigurationFilePath` environment variable
- UI tests: detected via `--uitesting` launch argument passed by `MenuBarTests.setUp()`

### Running Tests

- **Xcode**: `Cmd+U` runs both unit and UI test suites
- **CLI**: `xcodebuild -project KuKa.xcodeproj -scheme KuKa test`

### Unit Test Coverage

- `capture()` returns result on success, nil on screen capture failure
- Screenshots directory is created via `FileManaging` protocol
- Clipboard copy is called on successful capture, skipped on failure
- Coordinate conversion from NSView (bottom-left) to CGDisplay (top-left)
- File naming format: `Screenshot_YYYY-MM-DD_at_HH-MM-SS.png`
- `saveAnnotated()` writes file and updates clipboard
- `deleteScreenshot()` removes file and clears clipboard
- Keep Awake: activation passes the display-awake flag to the preventer; toggling it mid-session swaps the assertion without ending the session; timed sessions expire and fire callbacks; the menu panel reflects state and the display preference persists across launches
- Tiling layout math and the maximize/restore toggle, including apps that snap window sizes (`TilingLayoutEngine`)
- Screen-membership and screen-picking rules (`TilingScreenRules`), and the controller's saved-frame map behavior across save/restore/failure (`WindowTilingController`)
- Hotkey routing (`HotkeyManager`): tiling combos swallowed while enabled, passed through while disabled; screenshot combos work in both states

### Keep Awake implementation

- `IOKitSleepPreventer` creates an IOKit power assertion: `PreventUserIdleDisplaySleep` when "Keep display awake" is on (display and system both stay awake), `PreventUserIdleSystemSleep` when off (system stays awake, display sleeps and locks on its normal schedule).
- Lid-close sleep is never prevented; the menu hint says so.
- The display-awake preference lives in `UserDefaults` under `keepDisplayAwake`, default on.
- The menu UI is an inline custom-view panel (no submenu): one row of duration chips plus the checkbox; Turn Off appears below while a session is active.

### Window tiling implementation

- All layout math works on `visibleFrame` (menu bar and Dock excluded) in NS (bottom-left) coordinates.
- Stage Manager insets on maximize: 7% of visible width on the left (`stageManagerLeftInsetFraction`), 2% of visible *height* on top, bottom, and right (`stageManagerEdgeInsetFraction`; height-based on all three so the gaps are equal in points). Applied only when Stage Manager is on **and** the screen has 2+ windows — with one window the strip hides itself. Half-screen tiling gets no inset.
- Maximize/restore toggle: restore fires when the window's current frame matches the previously *achieved* frame (not the requested one) within 2 pt (`maximizeTolerance`). This handles apps like Terminal that snap sizes to a character grid.
- Screen rules: a window "belongs" to a screen when at least 50% of its own area intersects it; Stage Manager's own windows (owner `"WindowManager"`) and zero-area windows are excluded from the count. A window is tiled against the screen it overlaps the most; ties go to the lowest index, and with no overlap the controller falls back to `NSScreen.main`, then the first screen.
- AX safety: a 0.5 s `AXUIElementSetMessagingTimeout` cap stops a hung app from stalling the main thread; attributes are checked with `AXUIElementIsAttributeSettable` before writing; position is written before and after size for reliable edge snapping; the achieved frame is re-read and returned. Ku-Ka refuses to tile its own windows (pid check). Failures are only `NSLog`ged — no user feedback.
- The `windowTilingEnabled` `UserDefaults` key defaults to on. `WindowTilingController.savedFrames` entries for closed windows are never cleaned up (accepted for v1).
- `StageManagerDetector` reads `com.apple.WindowManager` / `GloballyEnabled` fresh on every access; this works because the app is unsandboxed.

### UI Test Coverage

- Menu bar status item exists
- Menu contains Launch at Login, Thumbnail Duration label, 3s/5s/Forever options, Quit
- Selecting a duration option persists across menu re-open
