# Settings window and summary tool

Task #43 moves persistent menu controls into one native Settings window. Operational commands remain in the menu. Existing defaults and saved values remain unchanged.

## Layout

Use one grouped, scrollable AppKit form in a reusable titled window. Changes save immediately. The menu has one **Settings…** entry with Command-comma. Command-W closes the window. Reopening brings the same window forward and refreshes its values.

```text
Ku-Ka Settings

General
  [ ] Launch at login
  [ ] Enable window tiling
  [ ] Record clipboard history
  [ ] Keep display awake during Keep Awake

Screenshots
  Show thumbnail for     [5 seconds v]
                         3 seconds / 5 seconds / 15 seconds / Forever

Meeting Notes
  Meetings folder        [path]       [Choose…]
  Summary tool           [Automatic v]
  Background file        [None]       [Choose…] [Clear]
```

The summary choices are **Automatic**, **Antigravity (agy)**, and **Claude Code (claude)**. Explain that Automatic tries Antigravity, then Claude Code. An explicit choice uses only that tool. Explain that the complete optional background file goes to the selected provider with the transcript. Clear removes the preference, never the file.

Use native controls, system colors, visible focus, accessible names, and logical keyboard order. Path labels must expose full paths without making the window grow. Settings, onboarding, and word review share activation handling, so closing one does not return the app to accessory mode while another remains open. Tests inject presentation and activation behavior. The image editor remains an NSPanel with its existing accessory-mode behavior, as confirmed by the task review.

## Preference inventory

| Preference | Storage | Default |
|---|---|---|
| Launch at login | SMAppService through LoginItemManaging | Actual service state |
| Window tiling | windowTilingEnabled | true |
| Clipboard history | clipboardHistoryEnabled | true |
| Thumbnail duration | thumbnailDuration | 5 seconds; choices 3, 5, 15, 0 |
| Display awake | keepDisplayAwake | true |
| Meetings folder | meetingsFolder | ~/Meetings |
| Summary tool | summaryTool, new | automatic |
| Background file | meetingContextFile, existing | None |

Keep Awake duration and Turn Off, recording controls, Show Meeting Controls, Restore Default Position, Check Words, Retry, Open Meetings Folder, permissions, help, and Quit remain commands. Restore Default Position is an immediate reset, although it removes stored coordinates. No new screenshot commands are required.

Keep knownWordsFile, meetingLocale, panel geometry, and onboarding bookkeeping unchanged. Opening Settings never writes defaults. A saved custom thumbnail value must remain intact until the user chooses another value.

## Ownership and job boundary

`Settings` owns persistence. `SummaryTool` is a three-case enum with one candidate list per case. `SettingsWindowController` owns the native window and actions; a separate view file may contain layout. `AppDelegate` connects its typed callbacks to existing runtime owners. Avoid a generic settings registry or observation framework.

`main.swift` selects one host through `AppLaunchMode`. XCTest has no application delegate and takes priority over `--uitesting`. The preview argument selects `SettingsPreviewAppDelegate`, with isolated defaults, inert login management, one Settings window, and a static menu. Production `AppDelegate` contains no test-mode branches. One title-and-duration table defines thumbnail choices, and each native menu item carries its duration directly.

At the start of each queued job, `MeetingNotesController` reads the tool preference once and passes the value through `MeetingProcessor` into `Summarizer`. Retry and Update Notes use this same boundary. A running transcription keeps its tool even if Settings changes before its summary. Queued jobs read the new choice when they start. Keep the setting out of queue identity.

Automatic keeps the current agy-then-claude fallback. Explicit choices have one candidate and return its existing useful failure details. Preserve executable search paths, invocation flags, timeout, empty working folder, fixed PATH, known-word filtering, context-file reads, review parsing, heard-text updates, and cancellation. `SummaryDocument` already omits CLI attribution; keep its output unchanged.

Move display-awake persistence into Settings under the same key and default. KeepAwakeController applies the value to WakeManager. Folder changes refresh menu counts but do not move files or change active and queued meeting paths. Launch-at-login reads back the service state and reports a failed change.

## Alternatives and synthesis

Two independent design sketches compared a single grouped form and native tabs. The cross-review selected the grouped form because the current controls fit, while Screenshots would have one control in a tab. Retain the tabbed proposal's explicit test-host isolation and job-start snapshot. Reject its one-field job-settings wrapper. Preserve all four thumbnail choices permanently; both sketches initially misread that detail.

Routine UX decisions are delegated by the task request. The text mockup was shown before implementation. No additional design approval is required.

## Integration with related tasks

The Settings owner owns the Meeting Notes group. Calendar #28 can add reminder and calendar-selection controls there once its owner provides the state and action API. Teams #41 can add preferences only after its investigation establishes a supported source. Both must use this window, with typed callbacks to their own controllers. Do not add placeholders, EventKit, Teams inspection, or a second Settings window. Keep those inputs distinct from the optional background file.

Likely shared conflicts are AppDelegate wiring, Settings keys, MeetingNotesController initialization, and current documentation. This branch does not merge siblings. The recording-hotkey branch must attach its presentation here when ready.

## Verification and limits

Use TDD through Settings, Summarizer, MeetingProcessor, MeetingNotesController, and native control actions. Use isolated defaults, fake login service, fake command runner, fake permissions and recording, and temporary meeting folders. Use build/task-verification for DerivedData. Never open real meeting contents or download models.

The source inventory records the before state. A live baseline screenshot attempt timed out in the native UI tool. The user then asked to stop the debug app; it was stopped and must stay closed. Capture native view evidence through isolated rendering if feasible. Do not claim a live keyboard or VoiceOver walkthrough from unit tests alone.
