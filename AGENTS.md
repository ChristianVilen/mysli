# Selected Area Screen Capture (app name Ku-Ka (kuvakaappaus))

## Overview

A lightweight macOS app to replace the default `Shift+Command+4` selected area screenshot functionality. The app will:

- Capture a user-selected area of the screen.
- Capture a window with `Shift+Command+4`, then `Space` and a click.
- Capture the full screen instantly with `Shift+Command+3` (captures the screen where the cursor is, with flash animation).
- Multi-monitor support — dims all screens, captures from the screen where the cursor is.
- Save the screenshot to `~/Screenshots/`.
- Copy the screenshot to the clipboard.
- Floating thumbnail preview after capture — click to annotate with freehand drawing.
- Delete screenshots from thumbnail or editor — removes file and clears clipboard.
- Keep Awake — prevent the Mac from idle-sleeping from the menu bar, for a preset time (30m/1h/2h/4h) or until turned off, with an optional "keep display awake" preference.
- Window tiling — `Ctrl+Option+Left/Right/Return/C` snaps the active window to the left half, right half, full screen, or center of its display (maximize toggles back to the previous frame; center keeps the window's size and does nothing when it's already maximize-sized). Pressing Left/Right again on an already-snapped window sends it to the same half of the next screen in that direction (wrapping — with two monitors, either direction reaches the other one). Stage Manager-aware, with a menu toggle to turn the hotkeys off.
- Clipboard history — `Shift+Command+C` opens a glass panel listing recorded clipboard items, newest first; typing filters, arrow keys select, Enter pastes into whatever app had focus. For rich text (RTF/HTML), Enter opens a chooser: paste with formatting or without, with "without" pre-selected. Records plain text, rich text, and images, including Ku-Ka's own screenshots — deleting a screenshot removes its history entry too. In-memory only, capped at 100 items and ~100 MB of image bytes; concealed/transient/auto-generated pasteboard content (password managers) is never recorded. A menu toggle stops polling, clears the history, and releases the hotkey.
- Meeting notes. **Start Recording Meeting** in the menu records the microphone ("Me") and the sound the Mac plays ("Them") through one ScreenCaptureKit stream. After Stop, Ku-Ka transcribes both tracks on the Mac with WhisperKit (model `large-v3-v20240930_turbo`), or with Apple's `SpeechTranscriber` when Whisper cannot start, merges them, and asks an AI command-line tool (`agy`, else `claude`) for a summary. Each meeting gets a folder `<meetings folder>/<yyyy-MM-dd_HH-mm>/` with `transcript.md` and `summary.md`. The audio goes to the Trash once the transcript exists. Only the transcript text leaves the Mac, as the CLI's prompt.

---

## Architecture

### File Structure

```
KuKa/
├── main.swift           # App entry point (NSApplication.shared.run())
├── AppDelegate.swift    # NSStatusItem menu bar, wires hotkey → overlay → capture → thumbnail → editor pipeline
├── HotkeyManager.swift  # Desired shortcuts, feature toggles, retry timer, wake handling and reported issues
├── HotkeyShortcut.swift # Seven shortcut definitions, actions, labels and registration failures
├── HotkeyRegistration.swift # CarbonHotkeyRegistrar: sole owner of active/pending-release registrations, reconciliation and event IDs
├── CarbonHotkeyAPI.swift # Five injectable Carbon calls; production defaults invoke macOS directly
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
├── TilingLayoutEngine.swift  # Pure layout math: target frame + move/restore/hop/center decision for left/right/maximize/center
├── TilingScreenRules.swift # Screen-picking, adjacent-screen (hop) picking + windows-per-screen counting (for the Stage Manager check)
├── StageManagerDetector.swift # Reads the system Stage Manager on/off setting, fresh on every access
├── AccessibilityWindowControl.swift # AX-API glue: reads/moves the focused window, NS-space coordinates
├── ScreenCoordinates.swift   # Shared top-left (CG/AX) <-> bottom-left (NS) coordinate flip
├── PermissionsManager.swift  # Single source of truth for Accessibility + Screen Recording status, polling, deep links
├── HotkeyHealth.swift   # Menu value built directly from permissions and registration issues
├── OnboardingWindowController.swift # Permission onboarding window: per-permission row with live ❌/✅ + Grant button
├── ClipboardItem.swift       # Pure value type: text (plain/RTF/HTML) or image (PNG + pixel size), content hash, preview label
├── ClipboardHistory.swift    # Pure model: ordered list, dedupe-to-top, item/byte caps with eviction, filter, remove-by-hash
├── ClipboardPasteboard.swift # SystemPasteboard (NSPasteboard.general read/write, marker-type skip) + CGEventKeystrokeSender (synthetic Cmd+V)
├── ClipboardHistoryController.swift # @MainActor: poll timer, owns ClipboardHistory + panel state, paste hand-off, enable/disable
├── ClipboardPanel.swift      # NSGlassEffectView panel: search field + NSTableView list, formatting chooser
├── ClipboardRowViews.swift   # Metrics (every size/inset the panel draws with) + the panel's row and cell views
├── ClipboardThumbnails.swift # ClipboardThumbnailCache: ImageIO decode at thumbnail size, keyed by content hash
├── PasteboardImage.swift     # The one image-write rule shared by ImageStore and SystemPasteboard: PNG always, TIFF while small enough
├── ContentHash.swift         # SHA-256 hex digest shared by ClipboardItem (dedupe key) and ImageStore (per-file tracking)
├── MeetingFolder.swift       # One meeting on disk: tracks, documents, the stage rule, naming, listing, atomic writes
├── Transcript.swift          # Pure: segment and line types, the merge, the echo rule, transcript.md
├── MeetingAudioCapture.swift # Capture seam, ScreenCaptureKit adapter, AudioTrackWriter (16 kHz CAF), AudioTimeline
├── RecordingAudioLevels.swift # Pure per-track level mapping and stale-reading expiry
├── RecordingAudioMeterView.swift # Native Microphone and Mac audio meters in the recording menu
├── MeetingTranscriber.swift  # Transcribing and TranscriptionSession seams, TranscriberFailure, and the SpeechAnalyzer adapter (the fallback)
├── WhisperKitTranscriber.swift # The only file that imports WhisperKit: model install, language codes, silence filter, WhisperKitClient seam
├── MeetingSummarizer.swift   # SummaryCLI table, Summarizer fallback, the prompt, summary.md
├── ProcessCommandRunner.swift # CommandRunning seam and ProcessCommandRunner: one child process with a given PATH and a timeout
├── MeetingProcessor.swift    # The pipeline after Stop: transcribe, then summarize, from whatever stage the folder is in
├── MeetingNotesController.swift # @MainActor: Meeting Notes menu section, recording state, processing queue, notifications
├── Notifier.swift            # Notifying seam and SystemNotifier: permission at a chosen moment, posts that open a file on click
├── Info.plist           # LSUIElement=true, NSScreenCaptureUsageDescription, NSMicrophoneUsageDescription
└── KuKa.entitlements    # Sandbox disabled for screen capture and Accessibility window control
```

`KuKa/` and `KuKaTests/` are file-system synchronized folders. Xcode compiles every
file in them, so adding, renaming, or deleting a source file changes nothing in
`KuKa.xcodeproj/project.pbxproj`. Do not add file entries to the project file by hand.
To keep a file out of the build, put it outside these two folders.

### Key Classes

| Class | Responsibility |
|-------|---------------|
| `AppDelegate` | Menu bar icon, launch-at-login toggle, Window Tiling toggle (persisted as `windowTilingEnabled`), thumbnail duration setting, orchestrates the capture flow, multi-monitor overlay management; owns `ClipboardHistoryController` and `ClipboardPanel`, wires the Clipboard History menu toggle (persisted as `clipboardHistoryEnabled`) to enable/disable and dismiss the panel; and wires `ImageStore.onDeletedHash` to `controller.removeItem(hash:)` so deleting a screenshot drops its history row. Owns `MeetingNotesController` (root read from `Settings.meetingsFolder`), wires its `onStateChange` to the icon and `onShowPermissions` to onboarding, calls `resumeUnfinished()` at launch outside tests and `shutDown()` at quit. Outside tests, installs `SystemNotifier.shared` as the notification center's delegate. While recording, it labels the status item for VoiceOver, sets a tooltip, shows a second status item with a stop button, and `applicationShouldTerminate` asks before Quit stops the recording |
| `HotkeyManager` | Owns feature toggles, the 5-second retry timer, wake/session observers, and reported issues. Calls `CarbonHotkeyRegistrar.reconcile(desired:)` and forwards its actions. Has no registration map or generation tokens. `stop()` reports any release failures; stop and deinit clean up the timer and observers. |
| `HotkeyShortcut` / `CarbonHotkeyRegistrar` | `HotkeyShortcut` defines each key, modifier set, label, and action. The registrar alone owns registration IDs and references in one map with active/pending-release states. It checks system conflicts, applies desired registrations, rejects stale events, retries releases, and reports failures even for disabled shortcuts. `CarbonHotkeyAPI` supplies five injectable C calls without any registration policy. |
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
| `KeepAwakeController` | Keep Awake AppKit glue: builds the menu section and its countdown title, persists the display preference, expiry notification. A `MenuSection`: `StatusMenu` refreshes it when the menu opens and once a second while it is open |
| `KeepAwakePanelView` | Custom `NSView` menu item: status line, duration chips (segmented control), "Keep display awake" checkbox |
| `WindowTilingController` | `@MainActor`, thin orchestrator: reads the focused window, picks its screen, asks `TilingLayoutEngine` what to do, carries it out through `WindowControlling`; owns the pre-maximize saved-frame map |
| `TilingLayoutEngine` | Pure, stateless layout math: target frame for left-half/right-half/maximize/center, whether a maximize should move the window or restore its pre-maximize frame, whether a second half-press should hop to the adjacent screen, and whether a center press should do nothing (window already maximize-sized) |
| `TilingScreenRules` | Screen-related rules: counts how many on-screen windows "belong" to a given screen (for the Stage Manager strip check), picks which screen a window should be tiled against, and picks the adjacent screen a second half-press hops to (ordered by horizontal center, wrapping) |
| `StageManagerDetector` | Reads whether Stage Manager is turned on, fresh on every access (no caching, since the user can toggle it any time) |
| `AccessibilityWindowControl` | Accessibility-API glue: reads the focused window's frame and moves/resizes it; converts between AX (top-left origin) and NS (bottom-left origin) coordinates |
| `WindowListProvider` | Lists on-screen, layer-0 windows (excluding Ku-Ka's own) via `CGWindowListCopyWindowInfo`, converted to NS coordinates |
| `ScreenCoordinates` | Shared vertical-flip math used by both `WindowListProvider` and `AccessibilityWindowControl` for CG/AX ↔ NS coordinate conversion |
| `PermissionsManager` | `@MainActor` single source of truth for the TCC permissions: `refresh()` re-reads `AXIsProcessTrusted()`/`CGPreflightScreenCaptureAccess()` and the Microphone status (`AVCaptureDevice`), request methods deep-link into the right System Settings pane (and trigger the system prompt — for Accessibility only on the first request, see below), 0.5s polling while onboarding is open. `requestMicrophone()` shows the system prompt when the user was never asked and opens the Microphone pane after a refusal. Microphone is not part of `allGranted`, so onboarding does not open at launch for people who never record a meeting |
| `HotkeyHealth` | A value containing `accessibilityMissing` and ordered registration `issues`. `AppDelegate.updateStatus()` builds it directly from the owners for the menu and icon. `StatusMenu` skips identical values before rebuilding its warnings. No monitor object, probe closures, or extra change callback. |
| `OnboardingWindowController` | Dedicated `NSWindow` (AppKit, no storyboard) for permission setup and the one-time screenshot shortcut setup page. Permission setup opens first when a grant is missing; screenshot conflicts are explained after that window closes, even if Accessibility was skipped. The menu's "Permissions…" and a capture blocked on a missing grant open the checklist. Flips the app to `.regular` activation policy while open, back to `.accessory` on close. The policy call is an injected closure, so tests record it instead of changing the test host. Each `PermissionRowView` shows granted (✅), missing (❌), or, for the optional Microphone before macOS asked, not asked yet ("–" with an Allow button) |
| `ClipboardItem` | Pure value type: kind is `.text(plain, rtf: Data?, html: Data?)` or `.image(png: Data, pixelSize)`, plus a content hash from the shared `ContentHash` — the same one `ImageStore` records per file, so the two agree on identity — copy date, `hasRichFlavors`, `byteCost`, and a one-line `previewLabel` built once up front |
| `ContentHash` | Neutral namespace for the SHA-256 hex digest (CryptoKit) that `ClipboardItem` uses as its dedupe key and `ImageStore` records for each PNG it copies |
| `PasteboardImage` | Neutral namespace holding the one image-write rule — PNG always, a TIFF representation alongside it only under a pixel ceiling — plus that ceiling's default. `ImageStore` and `SystemPasteboard` both write images to `NSPasteboard.general` and both call this instead of carrying their own copy |
| `ClipboardHistory` | Pure model, no AppKit: ordered list (newest first), dedupe-to-top on a matching content hash, a 100-item cap and a ~100 MB image-byte cap (each evicts oldest-first, text is never evicted by the byte cap), a single-item 50 MB refusal, case-insensitive filter, remove-by-hash, clear |
| `ClipboardPasteboard` | `SystemPasteboard` adapts `NSPasteboard.general` to `PasteboardReading`/`PasteboardWriting`: skips content carrying an `org.nspasteboard` concealed/transient/auto-generated marker, reads an image (`.png`, else `.tiff` re-encoded) or text plus `.rtf`/`.html`, writes plain-only or plain-plus-rich flavors and returns the change count the write itself produced (for self-write suppression). `CGEventKeystrokeSender` sends the synthetic Cmd+V (`kVK_ANSI_V`, `.maskCommand` only). The TIFF ceiling is an init parameter defaulting to `PasteboardImage.defaultTIFFMaxPixels` |
| `ClipboardHistoryController` | `@MainActor`. Runs a 0.5s main-queue poll against `PasteboardReading`, owns the `ClipboardHistory` and every piece of state the panel renders (visible items, selection, list/chooser mode). Handles Enter (paste, or open the formatting chooser for rich text), Esc, filtering, the paste hand-off (close panel → write → keystroke after a short settle delay, adopting the write's own change count as the new baseline), `enable()`/`disable()` (stop polling + clear), and `removeItem(hash:)` for screenshot deletions. Every panel entry point is mode-aware here — the panel forwards Enter, Esc, arrows, clicks and typing blindly and never second-guesses what the current mode allows |
| `ClipboardPanel` | Subclass of `FloatingPanel`, `.nonactivatingPanel` + `canBecomeKey` so it takes keystrokes without activating Ku-Ka. `NSGlassEffectView` background, a search field over an `NSTableView` list; renders whatever `ClipboardHistoryController` currently says to show and forwards key events back to it. View only — no history, no `NSPasteboard` access |
| `Metrics` / `ClipboardHistoryRowView` / `ClipboardHistoryCellView` | `ClipboardRowViews.swift`: every size and inset the panel draws with, the inset rounded selection bar (the full-width system band fights glass), and one row's icon + one-line label + trailing image thumbnail |
| `ClipboardThumbnailCache` | Decodes an item's PNG at thumbnail size through ImageIO — the full-resolution bitmap is never built — and keeps only the small result, keyed by content hash. Cleared on dismiss, so a deleted screenshot can't come back |
| `MeetingFolder` / `MeetingStage` | One meeting on disk and its file rules: dated name with `-2`, `-3` on a clash, a title read back from the name, listing oldest first, atomic text writes, `clearFailure()`, `discardAudio(trash:)`, and `lock()`: a `FileLock` on `<folder>/.lock` that gives one writer the folder across processes. `MeetingStage` (`pending(step)`, `failed(step)`, `done`) is never stored. `MeetingStage.init?(MeetingFolderContents)` derives it from which files exist, and nil means "not a meeting folder". `MeetingTrack` (`.microphone`, `.system`) is the one list of sources: file names derive from it. `MeetingStep` holds the menu and failure wording for each step |
| `Transcript` | Pure. `merge` interleaves the tracks by start time, drops microphone echoes of system segments, and joins a speaker's segments while the gap is under 2 s. `isEcho` is the echo rule. `markdown(_:title:duration:by:after:)` writes `transcript.md`, with a line that names the transcriber and lists what failed first, as `SummaryDocument` does for the summary |
| `FileLock` | An exclusive, non-blocking `flock` on one file. `acquire(at:)` creates the file and throws `FileLockError.held` when this process or another one holds it, or `.failed(reason:)`. `release()`, deinit, and the end of the process release it, so a crash leaves no stale lock. `MeetingFolder.lock()` and `WhisperKitTranscriber.download(for:)` use it |
| `MeetingProcessor` | `@MainActor`, holds no state. `process(_:onStep:)` holds the folder's lock and runs every step a folder still needs: start the first transcriber that can, transcribe each track with its one session, and write `transcript.md`, then move `audio/` to the Trash, summarize, and write `summary.md`. When no transcriber can start, `error.md` has one line for each of them. With no speech, it writes both files saying so, keeps the audio, and returns `.noSpeech`. A failure writes `error.md` and keeps the inputs of the failed step; so does a step that leaves the stage unchanged. A locked folder returns `.busy`, a missing one `.gone`. Cancellation (quit) marks nothing failed. The first run, launch recovery, and Retry all call it the same way |
| `Summarizer` / `SummaryCLI` / `ProcessCommandRunner` | `SummaryCLI` lists the CLIs in the order tried (`agy`, then `claude`), their search folders, and each one's invocation: arguments, and the prompt on stdin for `claude`. `Summarizer` tries each one until one exits 0 with output, and returns `.written` with the earlier failures or `.failed` with one `SummaryFailure` per CLI. It gives each CLI a `PATH` of the user tool folders and the system folders. `ProcessCommandRunner` (behind `CommandRunning`, in its own file) runs one child process with stdin from a temporary file holding `input` (or `/dev/null`), stdout and stderr in temporary files, an empty temporary working folder, the `PATH` it is given, and a timeout. On a timeout or task cancellation it sends SIGTERM, then SIGKILL after a 5 s grace period |
| `MeetingNotesController` | `@MainActor`. Builds the Meeting Notes menu section (a status line while starting or recording, the record action, progress, the waiting count, retry, open folder), owns the recorder state (`idle`, `starting`, `recording`), and runs the queue of stopped meetings through `MeetingProcessor` one at a time. Checks Screen Recording and Microphone at Start and shows an alert with the reason when Start fails (`alertStartFailure` is injected). Asks for notification permission at Start and posts its notifications through `Notifying`: short title-case titles, a click opens `summary.md`, `error.md`, or the folder, and raw tool output stays in `error.md`. As a `MenuSection`, it reads failed meetings from disk in `menuWillOpen()`, and `menuTick()` updates titles. A separate visible-menu timer reads the recording's audio levels. `waitUntilIdle()` is for tests |
| `SystemNotifier` / `Notifying` | The one way Ku-Ka posts notifications, used by Keep Awake and Meeting Notes. `requestPermission()` asks once per run, at a moment the user chose (a timed Keep Awake chip, Start Recording Meeting). `post(title:body:opening:)` stores a URL that opens on click. As the notification center's delegate it also shows banners while Ku-Ka is the active app |
| `ScreenCaptureMeetingAudio` / `ScreenCaptureRecording` / `AudioTrackWriter` | The capture adapter behind `MeetingAudioCapturing`. One `SCStream` with `.audio` and `.microphone` outputs on one serial queue. `ScreenCaptureRecording` (an `ActiveRecording`) owns the stream and one `AudioTrackWriter` per track, measures both tracks from the first buffer's presentation time, and reports an interruption once. `AudioTrackWriter` converts each buffer to 16 kHz mono 16-bit PCM, pads gaps with silence, and writes a CAF file |
| `Transcribing` / `TranscriptionSession` / `TranscriberFailure` | `Transcribing` is one speech-to-text engine with a `name`. `MeetingProcessor` owns an ordered list, `[WhisperKitTranscriber(), SpeechTranscriberAdapter()]` by default, and uses the first one whose `needsDownload(for:)`, `download(for:)` (when needed), and `load(for:)` succeed. `load` returns a `TranscriptionSession` that holds the model for one meeting and transcribes both tracks. `TranscriberFailure` records why a transcriber could not start: the stage (`unavailable`, `download`, or `load`) and the message. `MeetingProcessor` reports a download through `onDownload`, so the menu shows it as its own step |
| `WhisperKitTranscriber` / `WhisperKitClient` / `WhisperKitLibrary` | The default transcriber, named "Whisper large-v3-v20240930_turbo". `needsDownload(for:)` throws for a language that Whisper does not know, then checks that the model folder exists. `download(for:)` installs the model with a folder rename under a `FileLock`. `load(for:)` returns a session that holds the loaded model and the Whisper language code. `languageCode(for:)` maps a locale to Whisper's code, and `trackTranscript(_:duration:)` maps WhisperKit segments to a `TrackTranscript` and drops the silence phrases. `WhisperKitClient` is the seam: `WhisperKitLibrary` makes the real WhisperKit calls, and tests use a fake that never downloads or loads a model |
| `SpeechTranscriberAdapter` | The fallback, named "Apple speech recognition". `needsDownload(for:)` throws for a locale that `SpeechTranscriber.supportedLocales` lacks (exact BCP 47 match) and says whether the model is installed; `download(for:)` installs it through `AssetInventory`; `load(for:)` returns a session that holds the locale. The session's `transcribe(_:)` runs `SpeechTranscriber(locale:preset: .transcription)` and `SpeechAnalyzer` over one track file, returning `TrackTranscript` |

### Flow

```
Shift+Cmd+3 → HotkeyManager (registered shortcut) → AppDelegate.startCapture(.fullScreen)
→ Detect cursor screen → CaptureManager.captureFullScreen(screen) → Save PNG + Copy clipboard
→ FlashView.flash(on: screen) → ThumbnailPanel shown (bottom-right)

Shift+Cmd+4 → HotkeyManager (registered shortcut) → AppDelegate.startCapture(.interactive)
→ OverlayWindows shown on all screens → User drags selection on cursor's screen
→ SelectionView reports CGRect → All overlays dismissed → 50ms delay
→ CaptureManager.capture(rect, screen) → Save PNG + Copy clipboard
→ ThumbnailPanel shown (bottom-right, 5s timeout) → Click thumbnail → EditorWindow opens
→ Freehand drawing → Done → Overwrite PNG + Update clipboard

Ctrl+Opt+Left/Right/Return/C → HotkeyManager (registration released when the
"Window Tiling" menu toggle is off) → WindowTilingController.tile(action)
→ TilingLayoutEngine.resolve(action, ...) decides move-and-save, restore, screen hop, or nothing
→ AccessibilityWindowControl.setFrame(...) moves the window

Shift+Cmd+C → HotkeyManager (registration released when the "Clipboard History"
menu toggle is off) → AppDelegate.toggleClipboardPanel()
→ ClipboardPanel.show() (non-activating panel; the previously focused app keeps focus)
→ type to filter / arrows to select / Enter to paste (or open the with/without-formatting
chooser for rich text) → panel closes → ClipboardHistoryController writes the pasteboard
→ synthetic Cmd+V sent after a ~50ms delay

Start Recording Meeting (menu) → MeetingNotesController.toggleRecording
→ PermissionsManager: Screen Recording, then Microphone (system prompt when never asked)
→ MeetingFolder.create → ScreenCaptureMeetingAudio.start → one SCStream
→ AudioTrackWriter per track → audio/me.caf + audio/them.caf
Stop Recording → ActiveRecording.stop (files closed) → folder queued
→ MeetingProcessor.process: the first transcriber that starts (WhisperKit, else Apple)
→ one TranscriptionSession transcribes each track → Transcript.merge → transcript.md
→ audio/ to the Trash → Summarizer (agy, else claude) → summary.md
→ "Meeting Notes Ready" notification (a click opens summary.md)
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

- **Language**: Swift 5, macOS 26.0+ (raised for `NSGlassEffectView`, used by the clipboard history panel)
- **Build tools**: Xcode 26+ / Swift 6.2+ compiler in Swift 5 language mode. The shortcut owners use `isolated deinit` for main-actor resource cleanup.
- **Project format**: Xcode 16 synchronized folders (object version 77) — opening the project needs Xcode 16 or later
- **Frameworks**: AppKit, Carbon.HIToolbox (global shortcut registration), CoreGraphics, ScreenCaptureKit, ServiceManagement, ApplicationServices (Accessibility API for window tiling), ImageIO (clipboard-panel thumbnails), CryptoKit (SHA-256 content hashing, via `ContentHash`), AVFAudio (meeting audio files), AVFoundation (Microphone permission), Speech (`SpeechTranscriber`, the fallback), UserNotifications
- **Packages**: WhisperKit is the first third-party dependency. The Swift package https://github.com/argmaxinc/argmax-oss-swift is pinned to exactly 1.1.1, and only the KuKa app target links its `WhisperKit` product. Only `WhisperKitTranscriber.swift` and its tests import it
- **Permissions**: Accessibility (window move/resize and synthetic clipboard paste), Screen Recording (ScreenCaptureKit), Microphone (Meeting Notes only). Registering shortcuts requires neither permission; using their actions can still require a grant.
- **Launch at Login**: `SMAppService.mainApp.register()` / `unregister()`
- **Build flag**: the KuKa app target sets `OTHER_SWIFT_FLAGS = "-enable-upcoming-feature IsolatedDefaultValues"`. This exists because `WindowTilingController`'s init has default argument values (`AccessibilityWindowControl()`, etc.) that construct `@MainActor` types, and under Swift 5 language mode the compiler otherwise treats those defaults as evaluated outside the actor. The flag becomes redundant once the project moves to Swift 6 language mode, where this is the default behavior.

---

## Future Features

- **Screen Recording** — capture video of a selected area or full screen

---

## Implementation Notes

### Keyboard shortcuts
- All seven shortcuts use public Carbon `RegisterEventHotKey` registrations on the main actor. There is no keyboard event tap or Secure Input polling.
- Screenshot combinations use `kVK_ANSI_3/4` with `cmdKey | shiftKey`. Clipboard history uses `kVK_ANSI_C` with the same modifiers. Tiling uses `kVK_LeftArrow/RightArrow/Return/ANSI_C` with `controlKey | optionKey`.
- Carbon matches each registered combination; additional Command/Control/Option/Shift modifiers are not part of that registration. Ku-Ka no longer captures screenshot variants with extra modifiers.
- One `onAction` callback carries `HotkeyAction`. Turning a feature off unregisters its combinations so other apps can use them.
- Before registering, check enabled macOS shortcuts with `CopySymbolicHotKeys`. Do not assume a successful registration proves there is no conflict. If the lookup fails, report and retry rather than register blindly.
- Keep Shift+Command+3/4. If they conflict, the menu directs the user to Keyboard Settings > Keyboard Shortcuts > Screenshots to turn off the matching macOS bindings. Ku-Ka does not change system preferences.
- Show screenshot shortcut setup once when conflicts are first detected, after permission setup. The `didShowScreenshotShortcutSetup` setting persists across launches. Closing or choosing Later leaves the menu instructions available.
- Registration errors affect only their shortcut. A failed release stays in the registrar's pending-release state and remains visible even when that feature is disabled. `HotkeyManager` retries on its 5-second timer and menu open, preserving successful registrations. A newly enabled system conflict releases the affected registration. Wake/session activation renews registrations.
- The menu lists unavailable shortcuts and missing Accessibility permission together. It never assigns blame to an app or promises lock/unlock will fix an issue. The red dot in the icon's bottom-left corner means a shortcut or Accessibility problem; orange there means Screen Recording is missing. The recording mark (top-right) is a red dot with a white centre, so it does not depend on colour alone.
- Registration success is not a check of physical delivery, window movement, capture, or synthetic paste. In particular, paste can still fail in protected fields.

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

## Worktrees

Create git worktrees with `workmux add <branch>`, and remove them with `workmux remove` or `workmux merge`. Do not create worktrees in `.claude/worktrees/`, and do not use an agent tool's own worktree option. The project's workmux settings are in `.workmux.yaml`.

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
KuKaTests/                    # Unit tests (XCTest, macOS 26.0+)
├── CaptureManagerTests.swift # Tests for capture, save, clipboard, coordinate conversion, file naming
├── CaptureFlowTests.swift    # Selection-to-thumbnail pipeline: rect/window/cancelled selection, full-screen capture and its screen fallback, flash + thumbnail on success, silent no-op on failure
├── SelectionSessionTests.swift # Selection lifecycle: rect/window results carry the right screen, resume-once semantics, teardown ordering, mouse-driven key-screen election
├── ImageStoreTests.swift     # File naming/counting, clipboard copy (incl. TIFF size threshold), saveAnnotated, screenshot deletion, and the clipboard-history deletion hook (per-file content-hash tracking, onDeletedHash reporting)
├── DrawingViewTests.swift    # Tests for freehand drawing and image compositing
├── EditorWindowTests.swift   # Done saves the annotated image to its own file, Delete removes it, window size is capped by the injected screen's visible frame
├── ThumbnailStackManagerTests.swift # Tests for thumbnail stacking and timer logic
├── ScreenCoordinatesTests.swift # NS/CG/AX vertical-flip math and the "which screen owns this rect" picking rule
├── WakeSessionTests.swift    # Tests for the pure keep-awake session model
├── WakeManagerTests.swift    # Tests for keep-awake orchestration against a fake preventer
├── KeepAwakeControllerTests.swift # Tests for the Keep Awake menu section and persistence
├── TilingLayoutEngineTests.swift # Target frame math and move/restore decisions for left/right/maximize
├── TilingAdaptersTests.swift # TilingScreenRules screen-membership + screen-picking rules, AX/NS coordinate conversion
├── WindowTilingControllerTests.swift # Saved-frame map behavior: save-then-restore, failed moves, entry lifecycle
├── HotkeyManagerTests.swift  # Real registrar with fake Carbon calls: lifecycle, toggles, events, conflicts, retry, wake and failed releases
├── PermissionsManagerTests.swift # Permission status via injected probes: refresh + change detection, poll-timer pickup, Settings deep-link fallback order, the Microphone prompt and pane
├── OnboardingWindowControllerTests.swift # One-time screenshot setup, permission-window ordering, skipped Accessibility, matching shortcut instructions, the Keyboard Settings action, and the Microphone row
├── SettingsTests.swift       # Every settings key defaults and round-trips: thumbnail duration, window tiling, clipboard history, meetings folder, meeting locale, launch at login
├── StatusMenuTests.swift     # Menu structure; the Window Tiling and Clipboard History toggles (write settings, fire a callback, flip their checkmark); duration picking; launch-at-login; the keep-awake and recording icon dots; the Meeting Notes section
├── ClipboardHistoryTests.swift # Pure-model tests for ClipboardHistory: dedupe-to-top, item/byte caps and eviction, filter, remove-by-hash, clear
├── ClipboardHistoryControllerTests.swift # Controller tests against a fake pasteboard and keystroke sender: polling, the paste hand-off, the formatting chooser, self-write suppression, enable/disable, screenshot-hash removal
├── MeetingFolderTests.swift  # The stage rule, folder names and titles, the -2/-3 suffix, listing, the stage read from a real temporary folder, clearFailure, discardAudio, the folder lock
├── TranscriptTests.swift     # Merge order and joining, the echo rule (including a measured speaker echo), transcript.md and its transcriber line
├── WhisperKitTranscriberTests.swift # Whisper language codes, segment mapping and the silence filter, the model install and its lock, and the session, against a fake WhisperKitClient
├── RealMeetingAudioTests.swift # Skipped unless KUKA_MEETING_AUDIO is set: the real Whisper model on real audio, with timings
├── AudioTimelineTests.swift  # Silence padding for gaps on the shared timeline
├── MeetingSummarizerTests.swift # Failure lines, summary.md, the prompt, and the Summarizer fallback order, per-CLI arguments and PATH against a fake runner
├── ProcessCommandRunnerTests.swift # Real child processes: exit status, separate stdout and stderr, output over 64 KB, timeout, input on stdin or end of file, empty working folder and PATH, launch error, cancellation, SIGKILL for a child that ignores SIGTERM
├── MeetingProcessorTests.swift # First run, no speech, the speech model download in the configured locale, the fallback from Whisper to Apple, failures and error.md, retry from the failed step, recovery at each stop point, cancellation, a locked or missing folder, on a real temporary folder
├── MeetingNotesControllerTests.swift # Start, stop and interruption (also while starting) against a fake capture; permission paths; a second click while starting; launch recovery; retry; menu titles; quit
└── Mocks.swift               # MockFileManager, MockClipboard, MockScreenCapture, MockWindowListProvider, MockWindowControlling, MockStageManagerDetecting, FakeSleepPreventer, FakePasteboard, FakeKeystrokeSender, FakeNotifier, FakeMeetingAudioCapture, FakeActiveRecording, FakeTranscriber, FakeCommandRunner, and the makeTemporaryDirectory, waitUntil and localDate helpers
```

No `KuKaUITests` target exists yet; `AppDelegate`'s `--uitesting` guard (below) is ready for one but nothing currently exercises it.

### Test-Mode Guard

When running under XCTest, `AppDelegate` skips permission setup and shortcut registration. This avoids TCC prompts and real shortcut claims. The same `isTesting` guard skips `clipboardHistory.enable()` at startup so tests never poll the real pasteboard, and skips `meetingNotes.resumeUnfinished()` so tests never read the real meetings folder or start a transcription. `MeetingNotesController.init` and its default adapters touch no microphone, stream, disk, or process. Meeting tests use a temporary folder, never `~/Meetings`:
- Unit tests: detected via `XCTestConfigurationFilePath` environment variable
- UI tests: detected via the `--uitesting` launch argument (no UI-test target currently exists)

### Running Tests

- **Xcode**: `Cmd+U` runs the unit test suite
- **CLI**: `xcodebuild -project KuKa.xcodeproj -scheme KuKa test`
- **Real meeting audio**: `RealMeetingAudioTests` runs only with environment variables. "Meeting notes implementation" below gives the command.

### Unit Test Coverage

- `capture()` returns result on success, nil on screen capture failure
- Screenshots directory is created via `FileManaging` protocol
- Clipboard copy is called on successful capture, skipped on failure
- Coordinate conversion from NSView (bottom-left) to CGDisplay (top-left)
- File naming format: `Screenshot_YYYY-MM-DD_at_HH-MM-SS.png`
- `saveAnnotated()` writes file and updates clipboard
- `deleteScreenshot()` removes file and clears clipboard
- Keep Awake: activation passes the display-awake flag to the preventer; toggling it mid-session swaps the assertion without ending the session; timed sessions expire and fire callbacks; the menu panel reflects state and the display preference persists across launches
- Tiling layout math, the maximize/restore toggle (including apps that snap window sizes), the second-press screen hop, and center's move/no-op decision (`TilingLayoutEngine`)
- Screen-membership, screen-picking, and adjacent-screen (hop) rules (`TilingScreenRules`), and the controller's saved-frame map behavior across save/restore/failure plus center pass-through (`WindowTilingController`)
- Hotkey registration (`HotkeyManager`): desired capture/tiling/clipboard registrations, feature-toggle release, action delivery, repeated start, stale callback rejection, partial failures and recovery, system conflicts and settings changes, automatic retry, wake renewal, and stop/deinit cleanup. Tests exercise the real registrar through fake Carbon calls without claiming system shortcuts. Failed releases stay visible, reject events, prevent duplicate registration, and clear after successful retry.
- Permissions (`PermissionsManager`): `refresh()` reads the injected probes; `onChange` fires only on a real status change; the 0.5s poll and the app-activation monitor pick up a grant without a manual refresh; the Settings deep link tries the modern pane id first and falls back to the legacy one; the Accessibility prompt is shown on the first request only, in this run and in later ones, while the Settings pane opens every time
- Clipboard history model (`ClipboardHistory`): adding puts the newest item first; a duplicate content hash moves the existing item to the top instead of growing the list; the 101st item evicts the oldest; the image-byte budget evicts oldest images first and leaves text alone; an item over the single-item byte cap is refused; the filter matches text content and image labels case-insensitively; remove-by-hash and clear both work; `hasRichFlavors` is true only when RTF or HTML is present
- Clipboard history controller (`ClipboardHistoryController`) polling and state, against a fake pasteboard and a fake keystroke sender: a change-count bump reads and adds one item, an unchanged count reads nothing, marked/oversized/unsupported content from the reader is skipped; `enable()`/`disable()` start and stop the poll and clear the history; a reported screenshot hash drops its item
- Clipboard history controller paste handling: Enter pastes plain text and images immediately, and opens the formatting chooser for rich text; the chooser's two rows paste with and without formatting; Esc in the chooser restores the prior list selection (clamped if items were removed while it was open); a paste moves the pasted item to the top of the history and keeps its rich flavors even when the paste itself was plain-only; the poll right after our own paste does not re-record it (self-write suppression, via adopting the write's own change count as the new baseline)
- Settings (`Settings`): `clipboardHistoryEnabled` defaults to true and persists, same as the other toggles; `meetingLocale` defaults to `en-US` and reads the tag set with `defaults write`
- Screenshot deletion (`ImageStore`): remembers the content hash of the PNG behind each saved file; `delete(at:)` reports that hash through `onDeletedHash`, nothing for an unknown URL, and both hashes when a screenshot was re-saved after annotation
- Status menu (`StatusMenu`): feature toggle state and persistence, duration selection, launch at login, Keep Awake icon, individual shortcut failures alongside Accessibility permission, screenshot setup instructions and the Keyboard Settings action, repeated rendering without duplicates, and clearing resolved warnings.
- Hotkey health (`HotkeyHealth`): menu tests cover permission and registration problems together, recovery that keeps unrelated warnings, release-failure wording, and repeated rendering that preserves the same menu items.
- Meeting folder (`MeetingFolder`, `MeetingStage`): the stage for every combination of files, the dated name and its `-2` suffix, the title read back from the name, listing that skips folders without Ku-Ka's files, and the stage read from a real temporary folder as files appear and `error.md` goes; one lock holder at a time
- Transcript (`Transcript`): interleaving by start time with Them first on a tie, joining while the gap is under 2 s, the echo rule's 60% and 1 s limits, short replies kept, a measured speaker echo dropped, and the exact `transcript.md` text, with the transcriber line alone and with "Tried first:"
- Whisper (`WhisperKitTranscriber`, against a fake `WhisperKitClient` and a temporary models folder): the language code for each of ten tags (`nb-NO` gives `no`, `fil-PH` gives `tl`, `eo` gives none); segment times and text kept, and the silence phrases dropped at the 8 s limit; decoding options with no prompt and no first-token threshold; a download that installs the model only by the final rename; a failed download that keeps the partial folder, and the next download that resumes there; an unsupported language that throws whether or not the model is installed; a download while another holder has the lock; a session that sends Whisper's language code and maps the segments; a transcription error that names the track; an empty track that the model never gets
- Summary (`Summarizer`, `SummaryDocument`): `agy` first, `claude` as the fallback, each with its measured argument list and the user tool folders on its `PATH`; a missing CLI, a launch error, a non-zero exit with the stderr tail, empty output, and a timeout each give one failure line; the `summary.md` footer names the CLI and why earlier ones failed
- Child processes (`ProcessCommandRunner`): real `/usr/bin/true`, `/usr/bin/false`, `/bin/cat`, and `/bin/sh` scripts for exit status, 100 KB of output, the timeout, the input on stdin or end of file, the working folder and `PATH`, cancellation that stops the child, and SIGKILL after the grace period for a child that ignores SIGTERM
- Processing (`MeetingProcessor`): the first run writes both files and trashes the audio; Whisper loads once for both tracks and Apple is never touched; when Whisper is unavailable, cannot download, or cannot load, Apple transcribes and `transcript.md` says why, and the menu leaves the download step; when no transcriber can start, `error.md` has one line for each; a transcription error after a load fails the step without a fallback; a cancel during the Whisper download neither fails nor falls back; no speech ends the meeting with the audio kept; a failure writes `error.md` and keeps what the failed step needs; Retry starts at the failed step; a stop at each point resumes with only the missing steps; cancellation leaves the meeting pending; a folder another writer holds is left alone, and a missing folder ends without a failure
- Meeting notes controller (`MeetingNotesController`): start, stop, and interruption with a fake capture, including a capture that ends before Start returns; missing Screen Recording, a denied, granted, or refused Microphone prompt, and a capture that cannot start, each with the alert that says why; a second click during the prompt; launch recovery that queues each meeting once and leaves failed ones; Retry; the menu titles; quit while recording or processing
- Recording meters: independent track levels, the exact stale-reading boundary, silence and full scale, RMS from synthetic PCM with saved CAF samples and padding unchanged, real capture-adapter snapshots from synthetic buffers, Stop clearing levels and ignoring late buffers, actual menu indicator labels and values, stop and restart, interruption during startup, and updates through the real StatusMenu open and close events.

### Keep Awake implementation

- `IOKitSleepPreventer` creates an IOKit power assertion: `PreventUserIdleDisplaySleep` when "Keep display awake" is on (display and system both stay awake), `PreventUserIdleSystemSleep` when off (system stays awake, display sleeps and locks on its normal schedule).
- Lid-close sleep is never prevented; the menu hint says so.
- The display-awake preference lives in `UserDefaults` under `keepDisplayAwake`, default on.
- The menu UI is an inline custom-view panel (no submenu): one row of duration chips plus the checkbox; Turn Off appears below while a session is active.

### Permissions implementation

- The Accessibility grant needs the system prompt (`AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt`) at least once: that call is what puts Ku-Ka in the Accessibility list. Opening the pane by itself adds nothing, and the user would find no row to switch on.
- After that first time the prompt only repeats what the onboarding window says, as a modal on top of it, so `requestAccessibility()` shows it once and then only deep-links. The flag lives in `UserDefaults` under `didPromptForAccessibility`.
- Screen Recording keeps prompting on every request: `CGRequestScreenCaptureAccess()` is not a modal of the same kind, and macOS re-asks for this grant about once a month anyway.
- To test the first-run path again: `tccutil reset Accessibility com.kuka.screenshot` and `defaults delete com.kuka.screenshot didPromptForAccessibility`.
- Microphone uses `AVCaptureDevice.authorizationStatus(for: .audio)` and `requestAccess(for: .audio)`. macOS shows that prompt only while the status is not determined, so after a refusal `requestMicrophone()` opens the Microphone pane instead. Microphone stays out of `allGranted`. Meeting Notes checks it at Start, and the onboarding checklist has a row for it.

### Window tiling implementation

- All layout math works on `visibleFrame` (menu bar and Dock excluded) in NS (bottom-left) coordinates.
- Stage Manager insets on maximize: 7% of visible width on the left (`stageManagerLeftInsetFraction`), 2% of visible *height* on top, bottom, and right (`stageManagerEdgeInsetFraction`; height-based on all three so the gaps are equal in points). Applied only when Stage Manager is on **and** the screen has 2+ windows — with one window the strip hides itself. Half-screen tiling gets no inset.
- Maximize/restore toggle: restore fires when the window's current frame matches the previously *achieved* frame (not the requested one) within 2 pt (`frameMatchTolerance`). This handles apps like Terminal that snap sizes to a character grid.
- Screen hop: a Left/Right press on a window already sitting at that half's target (within the same 2 pt tolerance) moves it to the same half of the adjacent screen in that direction. Screens are ordered by horizontal center (`TilingScreenRules.adjacentScreenIndex`) and the step wraps, so with two monitors either direction reaches the other one. Judged against the ideal target, not an achieved frame — an app that snaps its size by more than 2 pt never hops and just gets the half re-applied (accepted).
- Center (`Ctrl+Option+C`): moves the window to the middle of the visible frame keeping its size. Does nothing when the window's size already matches the maximize target's size within 2 pt (position is ignored); with the Stage Manager strip taking space, "maximize size" means the inset stage target.
- Screen rules: a window "belongs" to a screen when at least 50% of its own area intersects it; Stage Manager's own windows (owner `"WindowManager"`) and zero-area windows are excluded from the count. A window is tiled against the screen it overlaps the most; ties go to the lowest index, and with no overlap the controller falls back to `NSScreen.main`, then the first screen.
- AX safety: a 0.5 s `AXUIElementSetMessagingTimeout` cap stops a hung app from stalling the main thread; attributes are checked with `AXUIElementIsAttributeSettable` before writing; position is written before and after size for reliable edge snapping; the achieved frame is re-read and returned. Ku-Ka refuses to tile its own windows (pid check). Failures are only `NSLog`ged — no user feedback.
- The `windowTilingEnabled` `UserDefaults` key defaults to on. `WindowTilingController.savedFrames` entries for closed windows are never cleaned up (accepted for v1).
- `StageManagerDetector` reads `com.apple.WindowManager` / `GloballyEnabled` fresh on every access; this works because the app is unsandboxed.

### Meeting notes implementation

- Recording meters read the same converted PCM that `AudioTrackWriter` writes. `append` returns RMS after a successful write, excluding timeline-padding silence. `ScreenCaptureRecording` keeps the latest per-track measurement and monotonic receipt time in a `RecordingAudioMeter` under a short `OSAllocatedUnfairLock`. Main-actor `ActiveRecording.audioLevels()` copies this scalar state without waiting on the audio queue or holding a lock during disk I/O. Each reading expires after 0.5 seconds. The pure model maps -60...0 dB to 0...1.
- `MeetingNotesController` shows a `RecordingAudioMeterView` below elapsed time while recording. Its 0.1-second common-mode timer runs only while the menu is open. `MenuSection.menuDidClose()` is a protocol requirement with a no-op default, and `StatusMenu` forwards the close event. Closing the menu, stopping, interruption, shutdown, and deinit invalidate the meter timer. The view owns no recording state. Quiet audio has no warning.

- The meeting folder is the only state that outlives a click. `MeetingStage` comes from the files: `summary.md` means done, `transcript.md` means the summary is next, and audio means the transcription is next. An `error.md` turns the next step into a failed step. No stage is stored anywhere.
- Every text file is written atomically (temporary file, then rename). The stage rule reads "`transcript.md` exists" as "transcription finished", so a half-written file must never exist under the real name.
- `MeetingProcessor.process` moves `audio/` to the Trash at the start of the summarize step, the first moment a transcript is known to be on disk. A failed transcription keeps the audio. So does a meeting with no speech: it writes `summary.md` first, which marks it done, so the summarize step never runs for it.
- At launch, `resumeUnfinished()` queues every pending meeting. Failed meetings wait for **Retry Failed Meeting**, which removes `error.md` and queues them, so the processor starts again at the failed step. Quit cancels processing and terminates a running CLI. Nothing is marked failed, so the next launch continues.
- One writer owns a folder at a time, also across two Ku-Ka processes (a debug build next to the installed app). On disk, a live recording looks like a crashed one, so the controller holds `MeetingFolder.lock()` while it records and the processor holds it for each run. A locked folder is skipped. The system releases the lock when the process ends, so crash recovery is unchanged. The recorder never writes after `stop()` returns.
- Threads: `MeetingAudioCapturing.start` is `@MainActor`, so `ScreenCaptureRecording.stream` is touched only there; the sample buffers run on the recording's own queue. The transcriber, session, and `WhisperKitLibrary` methods that do long work, `Summarizer.summarize`, and `ProcessCommandRunner.run` are `@concurrent`, so they stay off the main actor even after a move to Swift 6 or `NonisolatedNonsendingByDefault`, where a plain nonisolated async function would run on the caller's actor.
- The capture can end before `start` returns, while the controller is still `.starting` and drops the callback. `ActiveRecording.endReason` is set on the main actor before `onInterrupted` runs, and `start()` checks it once the handle is back.
- Capture uses one `SCStream` with `capturesAudio`, `captureMicrophone`, and only the `.audio` and `.microphone` outputs. Measured on macOS 27: both tracks arrive without a `.screen` output, both use the host clock (the first buffers were 70 ms apart), and a CAF file that `AVAudioFile` was writing is readable after `kill -9`. The microphone format depends on the device (24 kHz for AirPods, 48 kHz for the built-in microphone), so each `AudioTrackWriter` builds its converter from each buffer's own format.
- ScreenCaptureKit does not cancel echo (measured on laptop speakers). `Transcript.isEcho` drops a "Me" segment of 3 or more words that overlaps a "Them" segment in time (1 s slack) and shares at least 60% of its words with it.
- `MeetingProcessor` tries `WhisperKitTranscriber` first and `SpeechTranscriberAdapter` second. It uses the first one whose language check, download (when needed), and load succeed, and records a `TranscriberFailure` for each one before it. Nothing falls back after a load: a transcription error fails the step and writes `error.md`, so both tracks of a meeting always come from one transcriber. A cancellation (quit) is never a failure, also during a download. URLSession reports a cancelled download as `URLError(.cancelled)`, not `CancellationError`, so the processor checks `Task.isCancelled`. During a download the menu shows **Downloading speech model**, and after it, also after a failed one, **Transcribing** again.
- `transcript.md` names the transcriber under the duration: "Transcript by Whisper large-v3-v20240930_turbo." After a fallback, the line is "Transcript by Apple speech recognition. Tried first:" and one bullet for each failure, for example "- Whisper large-v3-v20240930_turbo could not download its model: The Internet connection appears to be offline." The no-speech transcript has the same line. When no transcriber can start, `error.md` has one line for each of them. This fact is written to disk because the processor keeps no state between runs, and the summary can run in a later launch. `Transcript.contentForSummary` removes the generated preamble through the speaker legend before the summary CLI receives the spoken content. Older plain transcript inputs remain unchanged.
- The Whisper model is in `~/Library/Application Support/Ku-Ka/whisper-models/`. It is not in `~/Documents`, because iCloud "Desktop & Documents" would sync the model. WhisperKit's hub code downloads into `~/Documents/huggingface` when it gets no folder, so `WhisperKitLibrary` gives an explicit folder to every call that can reach the network. Download and load mark only the model cache as excluded from backups. A failure to set that optional metadata is logged and does not prevent transcription.
- The model is installed when `<models folder>/large-v3-v20240930_turbo/` exists. That is the only install state. A download writes `.large-v3-v20240930_turbo.partial/` and renames it when the model and its tokenizer are complete. A quit or crash leaves only the partial folder, which means "not downloaded". The next download continues in it: WhisperKit skips each file whose etag matches and resumes its `.incomplete` files. The tokenizer (`openai/whisper-large-v3`) is not part of the model download, so `WhisperKitLibrary.download` fetches it too. An intact installation loads locally. WhisperKit 1.1.1 can try the Hub when local tokenizer files are missing or invalid, even with model downloading disabled.
- A download holds a `FileLock` on `<models folder>/.lock` and checks again for the installed folder after it gets the lock. The hub downloader appends to a fixed `<file>.incomplete` path, so two Ku-Ka processes in one partial folder would corrupt the files. When another Ku-Ka holds the lock, the download fails with "Another Ku-Ka is downloading the Whisper model.", and Apple transcribes that meeting.
- Whisper gets the language part of `meetingLocale` as its own code, from `WhisperKitTranscriber.languageCode(for:)`. The valid codes are WhisperKit's `Constants.languages`. Whisper spells three of them differently from BCP 47: `nb` is `no`, `jv` is `jw`, and `fil` is `tl`. Whisper supports Finnish. For a language that Whisper does not know, `needsDownload(for:)` throws before any download, and Apple is tried.
- Whisper decodes with the options of the measured `whisperkit-cli` run (`WhisperKitLibrary.decodingOptions(languageCode:)`): VAD chunking, special tokens skipped, the prefill prompt, 4 concurrent workers, and Core ML on the CPU and Neural Engine. It gets no prompt (`promptTokens`), because the prompt's words leaked into the transcript when measured. It also gets no first-token threshold, as in the CLI. The library's default (-1.5) ends a segment when its first token is weak and decodes it again with random sampling. Measured on real audio, that dropped whole sentences, and two runs gave transcripts that differed on 126 lines. Without the threshold, two runs gave the same text. A unit test pins both options.
- `WhisperKitLibrary.LoadedModel` owns the VAD chunk path and checks every chunk's `Result` before applying timestamp offsets. WhisperKit 1.1.1's high-level VAD API logs and drops failed chunks, so it must not decide whether a track succeeded. A chunk failure fails the whole track and keeps the audio for retry. Model-free tests inject a failed chunk through the real WhisperKit adapter and verify successful chunk timestamps.
- Cancellation is checked after transcriber startup and each track returns, including a successful return from a cancelled task. No transcript, no-speech summary, or error is written for a cancelled transcription. Tests cover both empty and nonempty successful results after cancellation.
- One load serves both tracks. Measured with `RealMeetingAudioTests` on an M5 Pro, Release build, a 66.5-minute meeting: 86 s for the Them track and 61 s for the Me track, the same in two runs. The download took 49 s. The first load took 57 s, because it also compiles the model for this Mac. Later loads took 0.6 s. macOS removes the compiled model after an OS update or a long time without use.
- `WhisperKitTranscriber.trackTranscript` drops the phrases that Whisper writes over silence. Measured with `whisperkit-cli --report` on a 66-minute meeting: "Thank you." came 99 times on Me and 22 times on Them. All 99 on Me and 18 of the 22 on Them lasted 9 to 30 s. The other 4 lasted 1 to 5 s and can be real speech. 5 segments on Me were only "." and lasted about 18 to 23 s. `noSpeechProb` was 0 for every segment, and the `avgLogprob` of the silence lines (about -0.2) was the same as for real speech, so neither can be the filter. The rule: drop a segment with no letter or digit, and drop a segment that says only "thank you" (case and punctuation ignored) and lasts 8 s or more. About a quarter of the Them segments (124 of 517) start in lowercase. Most are fragments without punctuation, and the filter keeps them.
- `RealMeetingAudioTests` runs the real model on real audio, so a unit test run never downloads or loads it. It is skipped unless `KUKA_MEETING_AUDIO` names a folder with `me.caf` and `them.caf`. It then needs `KUKA_WHISPER_MODELS`, the models folder (it downloads the model there when missing), and `KUKA_TRANSCRIPT_OUT`, where it writes `transcript.md` and `timings.txt`. `timings.txt` has the download and load seconds, and the audio and wall-clock seconds of each track. The language is the app's `meetingLocale`. xcodebuild passes environment variables to the tests only with a `TEST_RUNNER_` prefix:

  ```bash
  TEST_RUNNER_KUKA_MEETING_AUDIO="$HOME/Meetings/2026-10-23_14-02/audio" \
  TEST_RUNNER_KUKA_WHISPER_MODELS="$HOME/Library/Application Support/Ku-Ka/whisper-models" \
  TEST_RUNNER_KUKA_TRANSCRIPT_OUT="$HOME/whisper-check" \
  xcodebuild -project KuKa.xcodeproj -scheme KuKa test -only-testing:KuKaTests/RealMeetingAudioTests
  ```

- The fallback, `SpeechTranscriber(locale:preset: .transcription)`, reads each track file after Stop, in the locale from the `meetingLocale` defaults key (default `en-US`, read at each use). It needs no speech-recognition permission and no `NSSpeechRecognitionUsageDescription` (measured). One result is a sentence or longer. Measured on macOS 27: the supported locales cover English, German, Spanish, French, Italian, Portuguese, Japanese, Korean, Chinese and several Indian languages, not Finnish; only the English models come installed. The summary prompt asks for notes in the transcript's language with English section headings.
- Each CLI runs by absolute path from `/opt/homebrew/bin`, `/usr/local/bin`, or `~/.local/bin`, because a GUI app does not get the shell's `PATH`. The child gets a fixed `PATH`, an empty temporary working folder (so it reads no project files or instructions such as `CLAUDE.md` and asks for no workspace trust), and a 10-minute timeout. Its stdin, stdout and stderr are temporary files, because a pipe holds 64 KB and a child that fills it blocks.
- `agy` gets `--sandbox --disable-slash-commands -p <prompt>`. Its flags must come before `-p`, or `agy` reads the flag as the prompt. Measured: `-p` needs the prompt as its value (text mode does not read stdin), `--mode plan` has no effect together with `--disable-slash-commands`, no flag turns tools off (only a user's own hook blocks them), and every run is saved under `~/.gemini/antigravity-cli/conversations/`. The prompt asks it not to use tools and not to follow instructions inside the transcript.
- `claude` gets `-p --tools "" --no-session-persistence --strict-mcp-config` and the prompt on stdin, so the transcript does not show in `ps`. `--bare` does not work with a subscription login, because it forces an API key.
- For `agy`, the transcript is one command-line argument. `ARG_MAX` is 1 MB, which fits about 15 hours of speech. A longer one fails to start `agy`, and `claude` gets it on stdin.
- The `meetingsFolder` key in `UserDefaults` sets the meetings root (`defaults write com.kuka.screenshot meetingsFolder <path>`). The default is `~/Meetings`, outside the folders that iCloud "Desktop & Documents" syncs. The controller reads the setting at each use, so a change applies without a relaunch.
- Without the Screen Recording grant, `SCShareableContent` fails with `SCStreamErrorDomain` -3801. Start checks the grant first and shows an alert that offers the permissions window instead.
- macOS does not add an app that runs from `/private/tmp` to the Screen Recording list. Run test builds of a capture change from another folder.
