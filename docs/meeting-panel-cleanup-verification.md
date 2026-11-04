# Meeting panel cleanup verification

Verified on 2026-11-03 for issue #55. After the code-review fixes, the full macOS XCTest run passed 1,108 tests, with five optional skips and no failures.

## Code-review fixes

- B1. The panel owns its content mode. The recorder supplies status, time, and an independent live preview on demand. Stopped notes have their own presentation.
- B2. A session row split saves and publishes one complete document. Its inverse restores only the affected rows. Native text and structural edits share one undo manager. Model tests count saved snapshots, and a native test types, splits, types in the new row, undoes all three actions, then redoes them and checks disk text and editor identity.
- B3. `MeetingScreenshot` validates input once. `MeetingScreenshotStore` owns bounded, safe file reads and immutable writes. Tests cover PNG, TIFF conversion, size limits, unsafe names, symlinks, and file permissions.
- S1. Existing row and screenshot views survive insertion. Retained thumbnails use small ImageIO decodes. A cache test removes the source file after the first decode and confirms the same thumbnail is reused.

Independent review found no blockers in the refactor. Native light and dark views were inspected again. These changes preserve the reviewed interface.

## Native and storage checks

`MeetingCombinedPanelTests` uses fake capture and live transcription with real AppKit editors. It verifies text saves, undo after rehosting, Enter and Shift+Enter, PNG paste and preview, and a local PNG dropped through the notes container. It also checks collapse without losing the editor, transcript switching, explicit close, post-Stop editing and resizing after the recorder notice expires, and rehosting old notes when a new recording starts.

`MeetingTypedNotesWindowTests` verifies the shared editor in its historical floating host. The checks cover undo and redo on disk, copy and paste, summary status, recovery from save errors, explicit reload confirmation, activation, minimum-width bounds, and detach without closing the session.

`MeetingNoteEntriesTests` checks the readable Markdown round trip, legacy notes, empty placeholders, first-content timestamps, multiple pause gaps, immutable PNG storage, and retained attachments after failed note saves. Invalid delimiter order and duplicate row IDs preserve the external document as undated legacy text. A failed image validation or write does not consume a placeholder's first-content timestamp.

`MeetingTranscriptSelectionTests` exercises native copy across messages, timestamps on consecutive messages from one speaker, and selection retention across appends and draft replacement. Native raster checks catch pill paint outside its bounds. Reduce Motion opens the transcript at full opacity immediately. The live model tests pin file-time timestamps and bottom draft ordering. Summary prompt tests require timestamp correlation and state that screenshot pixels are not supplied.

## Review and visual checks

Independent review found malformed-document slicing, timestamps assigned to empty placeholders, and a missing resize control after Stop. Regression tests cover the corrections. A separate transcript review led to retaining the rendered prefix rather than formatting the whole meeting on each draft update.

Native light and dark images were inspected for the combined panel and notes after Stop. Initial images exposed a zero-height note document, a fade that ignored Reduce Motion, and a pill fill that painted over the transcript header. The fixes address those causes. Final images show readable transcript and notes regions with an available notes resize handle.

The final result bundle contains no Auto Layout warnings. Two priority-inversion warnings originate in existing `LogFilesTests`. Xcode also reports the existing Info.plist resource warning. These did not fail the test run.

## Repeat the checks

Create one task output directory, then run the complete suite with optional native images enabled.

```sh
task_output=$(mktemp -d "${TMPDIR:-/tmp}/codex-task-XXXXXX")
TEST_RUNNER_MYSLI_COMBINED_SNAPSHOTS="$task_output/combined" \
TEST_RUNNER_MYSLI_TYPED_NOTES_SNAPSHOTS="$task_output/notes" \
TEST_RUNNER_MYSLI_PANEL_SNAPSHOTS="$task_output/panel" \
xcodebuild -quiet -project Mysli.xcodeproj -scheme Mysli \
  -destination 'platform=macOS' -derivedDataPath "$task_output/build" \
  test -only-testing:MysliTests
```

Inspect the native images and the Xcode result bundle. After all commands finish, remove only this task's output directory.

## Limits

Verification used synthetic audio events and temporary meeting folders. It did not record a real call, request permissions, download models, invoke a real summary provider, or replace the installed app. The native glass view and accessibility fallback are exercised by panel tests. Offscreen images use a solid material fallback because they do not reproduce the desktop compositor's glass effect.

Screenshot files are note attachments. The current summary CLI gets text, timestamps, and relative image references, not image pixels.
