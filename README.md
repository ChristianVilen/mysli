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
- Clipboard history — `Shift+Command+C` opens a searchable list of what you've copied, text and images, and pastes the item you choose back into the app you were using
- Meeting notes. Record a call from the menu bar, and Ku-Ka writes a transcript and a summary as Markdown files. Transcription runs on your Mac.
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

## Clipboard History

Press `Shift+Command+C` and a panel opens over whatever you're doing, listing what you've copied recently, newest first. Start typing to filter the list, use the arrow keys to move through it, and press `Enter` to paste the selected item into the app you were working in. The panel closes and that app keeps focus.

If the item is formatted text (say, from a web page or a rich-text editor), `Enter` asks first: paste with formatting or without. Without formatting is pre-selected, so pressing `Enter` twice gives you plain text. Plain text and images paste right away, with no second step.

Text and images both get recorded, including screenshots Ku-Ka itself saves to your clipboard. Delete a screenshot from its thumbnail or the editor and its clipboard history entry goes with it.

The history lives in memory only — nothing is written to disk, so it's empty again after a restart. It holds at most 100 items; images are capped at about 100 MB in total, with the oldest images dropped first. A single item over 50 MB is not recorded. Copies that your password manager marks as sensitive are never recorded.

The whole feature can be turned on and off with the **Clipboard History** checkbox in the menu bar menu (under Settings); the choice is remembered across restarts. While it's off, Ku-Ka stops recording, clears the history it collected, and gives `Shift+Command+C` back to other apps. With the feature on, Ku-Ka takes that shortcut from Chrome and Arc (Inspect Element), Xcode (Activate Console), VS Code (Open External Terminal), and Finder (Computer window).

## Meeting Notes

When a call starts, open the Ku-Ka menu and choose **Start Recording Meeting**. Ku-Ka records your microphone and the sound your Mac plays, so any call app works. While Ku-Ka records, its menu bar icon shows a red record mark (a red dot with a white centre) in its top-right corner, and a stop button appears next to it. When the call ends, click the stop button or choose **Stop Recording Meeting**. If Start cannot record, for example because a permission is missing, an alert says why.

While recording, open the menu to check the **Microphone** and **Mac audio** meters below the timer. Each meter shows the sound level on that track. An empty meter can mean silence or that no audio is arriving. A reading clears after half a second without new audio. The meters update only while the menu is open.

Ku-Ka then transcribes the call on your Mac with Whisper (the `large-v3-v20240930_turbo` model, through WhisperKit) and asks an AI command-line tool for a summary. It tries Antigravity (`agy`) first and Claude Code (`claude`) if that fails. Install at least one of them in `/opt/homebrew/bin`, `/usr/local/bin`, or `~/.local/bin`, and log in to it once in Terminal. A notification tells you when the notes are ready; click it to open the summary. Ku-Ka asks for notification permission the first time you start a recording. Each meeting gets its own folder, for example `~/Meetings/2026-10-23_14-02/`, with `transcript.md` and `summary.md`.

In the transcript, "Me" is you (the microphone) and "Them" is everyone else (the sound your Mac plays). Headphones give the cleanest transcript. On speakers, your microphone also hears the other people. Ku-Ka removes those repeated lines from "Me" when it finds them.

The first meeting downloads the Whisper model, about 1.5 GB, to `~/Library/Application Support/Ku-Ka/whisper-models`. Ku-Ka excludes this model cache from Time Machine backups. The menu shows **Downloading speech model** meanwhile. After that, transcription needs no network while the model and tokenizer files remain intact. If Ku-Ka cannot download or load the model, or Whisper does not know the language, Ku-Ka transcribes with Apple's speech recognition instead. The top of the transcript names the transcriber and, after a fallback, says why Whisper was not used. These diagnostics stay in the transcript file and are left out of the summary input.

Only the transcript text goes to the AI tool. Audio never leaves your Mac. `agy` keeps a copy of each transcript in its own conversation history; `claude` runs without saving a session. Ku-Ka moves the audio files to the Trash when the transcript is written, so you can still restore them from there.

If nobody spoke, the meeting ends without a summary and keeps its audio, so you can listen to it. If a step fails, the meeting folder gets an `error.md` with the reason, and the menu shows **Retry Failed Meeting**. Retry continues from the step that failed. If Ku-Ka quits or crashes during a meeting, it finishes the notes from the saved audio the next time it starts. To give up on a meeting, delete its folder. **Open Meetings Folder** in the menu opens the folder that holds them.

To keep the notes in another folder, set the path in Terminal:

```bash
defaults write com.kuka.screenshot meetingsFolder /path/to/folder
```

Ku-Ka uses the new folder the next time it needs it, without a restart. Do not use `~/Documents` or `~/Desktop` when iCloud syncs them, because the audio would then leave your Mac.

Ku-Ka transcribes US English by default. To transcribe another language, set its tag in Terminal:

```bash
defaults write com.kuka.screenshot meetingLocale de-DE
```

Whisper uses only the language part of the tag, so `fi-FI` gives Finnish. The Apple fallback needs a tag that Apple's speech recognition supports exactly, for example `en-GB`, `de-DE`, `fr-FR`, `es-ES`, `it-IT`, `pt-BR`, `ja-JP`, `ko-KR`, or `zh-CN`. Apple does not support Finnish. If neither can transcribe the language, the transcription fails, and `error.md` gives the reason for each. The summary is written in the language of the transcript.

Recording needs the Screen Recording permission (for the sound your Mac plays) and the Microphone permission. Ku-Ka asks for Microphone the first time you start a recording.

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 26+ (to build)

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

1. Open `KuKa.xcodeproj` in Xcode 26 or later
2. Select the `KuKa` scheme and your Mac as the destination
3. `Cmd+R` to build and run

## Permissions

Screen Recording lets Ku-Ka take screenshots and record the sound of a call for Meeting Notes. Accessibility lets it move windows and paste from clipboard history. On first launch, a setup window explains these permissions. Grant the permissions for the features you use; each row updates after you allow it in System Settings. Open the window again from **Permissions…** in the menu. A red dot in the bottom-left corner of the menu bar icon means an Accessibility or shortcut problem. An orange dot in that corner means Screen Recording is missing, when no red warning is present.

### Accessibility (window tiling and automatic paste)
Accessibility lets Ku-Ka move and resize windows and paste items from clipboard history. Registering the shortcuts does not need this permission.

**System Settings → Privacy & Security → Accessibility** → Enable Ku-Ka

Ku-Ka detects the permission when it becomes active or you open its menu. You do not need to restart it.

### Screenshot shortcut setup

Ku-Ka keeps `Shift+Command+3` and `Shift+Command+4`. If macOS already uses them, Ku-Ka shows a screenshot setup window once, after permission setup, and lists the conflicts in its menu. Choose **Open Keyboard Settings…**, then **Keyboard Shortcuts → Screenshots**, and turn off the matching macOS shortcuts:

- **Save picture of screen as a file** — `Shift+Command+3`
- **Save picture of selected area as a file** — `Shift+Command+4`

Ku-Ka retries within a few seconds. The menu warnings disappear when the shortcuts are ready. It does not change system settings for you. If you choose **Later**, you can return to the instructions through the menu's conflict warning.

All Ku-Ka shortcuts use registered macOS hotkeys instead of a keyboard event tap. The menu lists registration failures for each shortcut; other registered shortcuts remain available. If a shortcut cannot be released, Ku-Ka reports it and retries while running. Opening clipboard history and pasting are separate operations, so automatic paste can still fail in protected fields.

### Screen Recording (required)
ScreenCaptureKit requires screen recording permission to capture screen content. Meeting Notes also needs it to record the sound your Mac plays.

**System Settings → Privacy & Security → Screen Recording** → Enable Ku-Ka

Two macOS quirks to expect: the first capture can require one quit-and-reopen of Ku-Ka before the grant takes effect, and roughly every month macOS makes every screenshot app ask again for screen recording. Neither is something Ku-Ka can turn off.

### Microphone (Meeting Notes)
Microphone lets Ku-Ka record your side of a meeting. Only Meeting Notes needs it, so the setup window does not open for it at launch. Ku-Ka shows the macOS prompt the first time you choose **Start Recording Meeting**. If you said no, an alert offers **Open Permissions**; there, **Grant** opens the Microphone pane. Until you are asked, the Microphone row shows "–" and **Allow** instead of ❌, because the permission is optional.

**System Settings → Privacy & Security → Microphone** → Enable Ku-Ka

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
- **Clipboard History** — Turn clipboard recording and the `Shift+Command+C` hotkey on or off (remembered across restarts)
- **Thumbnail Duration** — Choose how long the floating thumbnail stays visible: 3 seconds, 5 seconds, 15 seconds, or Forever (until dismissed)
- **Keep Awake** — Keep the Mac from sleeping for a preset time (30 minutes, 1, 2, or 4 hours, or until turned off), with a "Keep display awake" checkbox
- **Start Recording Meeting** and **Stop Recording Meeting** start and stop a meeting recording. While Ku-Ka records, a line above them shows the elapsed time. While Ku-Ka makes notes, a line shows the step and how many meetings wait.
- **Retry Failed Meeting** appears when a meeting's transcription or summary failed.
- **Open Meetings Folder** opens the folder that holds the meeting notes.
- **Quit Ku-Ka** — Exit the app

## File Structure

```
KuKa/
├── main.swift           # App entry point
├── AppDelegate.swift    # Menu bar setup, wires hotkey → overlay → capture → thumbnail → editor
├── HotkeyManager.swift  # Desired shortcuts, feature toggles, retry and wake recovery
├── HotkeyShortcut.swift # Shortcut definitions and registration failures
├── HotkeyRegistration.swift # Registration state, reconciliation, conflict checks and failed-release recovery
├── CarbonHotkeyAPI.swift # Injectable macOS calls
├── HotkeyHealth.swift   # Permission and shortcut issues displayed by the menu
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
├── MeetingFolder.swift       # One meeting on disk and the rule that reads its stage from the files
├── Transcript.swift          # Merges the two tracks, drops echoes, writes transcript.md
├── MeetingAudioCapture.swift # Records the microphone and system audio into two CAF files
├── MeetingTranscriber.swift  # The transcriber seam and the fallback, Apple's SpeechTranscriber
├── WhisperKitTranscriber.swift # On-device transcription with WhisperKit: model download, languages, silence filter
├── MeetingSummarizer.swift   # Runs agy or claude for the summary, writes summary.md
├── MeetingProcessor.swift    # Transcribes, then summarizes, from wherever a meeting stopped
├── MeetingNotesController.swift # Meeting Notes menu section, recording state, and processing queue
├── Info.plist           # App config (LSUIElement, screen capture and microphone usage)
└── KuKa.entitlements    # Entitlements (sandbox disabled)
```

## Known Limitations

- Turn off the matching macOS screenshot shortcuts to let Ku-Ka register `Shift+Command+3/4`. With those macOS bindings off, quitting Ku-Ka leaves those two shortcuts unassigned until you restore them in System Settings.
- `Ctrl+Option+Left/Right/Return` are intercepted globally while window tiling is enabled, even inside apps that use those same keys for something else. Turn off **Window Tiling** in the menu to give the keys back to other apps.
- `Shift+Command+C` is intercepted globally while clipboard history is enabled, including in apps that use it for something else. Turn off **Clipboard History** in the menu to give the key back.
- The automatic paste can't reach password fields or apps that block synthetic key events. The item is still on the clipboard, so pasting it by hand (`Cmd+V`) works.
- No preferences UI for changing the shortcut keys, including the window tiling hotkeys
- Some windows can't be tiled — apps that don't let their windows be moved or resized through the Accessibility API, and Ku-Ka's own windows. The hotkey then does nothing; there is no error message.
- Meeting Notes transcribes one language per meeting, set with `meetingLocale` (US English by default), and it labels speakers only as "Me" and "Them".
- On speakers, a repeated line of fewer than 3 words can stay in the transcript as yours.
- A meeting recording is tied to a display. If that display goes away (for example, the external monitor of a closed laptop), the recording stops, Ku-Ka says so, and it makes notes from what it recorded.
- While `agy` is not logged in, it waits about 60 seconds before it fails, so the summary comes later. The summary's last lines say why `agy` was skipped.
- `agy` has no option that turns its tools off. Ku-Ka runs it with `--sandbox` and tells it not to use tools or follow instructions in the transcript, but only your own `agy` configuration (for example a pre-tool hook) can block its tools. `claude` runs with every tool turned off.

## Testing

### Running Tests

- **Xcode**: `Cmd+U` runs the unit test suite
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
- Shortcut registration, feature toggles, action delivery, conflict detection, partial failure recovery, wake renewal, stale callback rejection, and cleanup
- Meeting notes: the stage rule and folder rules on a real temporary folder, the transcript merge and echo rule, the transcriber fallback from Whisper to Apple, the Whisper model install, language codes, and silence filter against a fake WhisperKit, the summary fallback from `agy` to `claude`, child processes with real executables, recovery and retry from each step, and the recording controller with a fake capture

Unit tests never download or load the Whisper model. `RealMeetingAudioTests` runs the real model on your own meeting audio, and it is skipped unless you set its environment variables. `AGENTS.md` describes how to run it.

### Test-Mode Guard

When running under XCTest, the app skips real shortcut registration, permission setup, clipboard polling, and meeting recovery. Meeting tests use a temporary folder, never `~/Meetings`. Tests use the real registrar with fake Carbon calls. Detection uses `XCTestConfigurationFilePath` (unit tests) and the `--uitesting` launch argument (no UI-test target currently exists).

## Acknowledgements

Meeting Notes transcribes with [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) (`argmaxinc/argmax-oss-swift`), which is under the MIT License.
