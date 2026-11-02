# Typed meeting notes verification

The feature uses a separate native notes window and keeps the live transcript drawer. All verification uses synthetic meetings and temporary folders.

## Tests

The final full-suite run passed on 2026-10-30. Xcode executed 1,015 tests with 1,009 passes, six optional skips, and no failures. The optional tests require real audio, models, or a screenshot output directory. The separate native snapshot run passed all 56 selected tests.

The first tests ran before implementation. `testInitialSummaryIncludesTypedNotesSeparatelyFromTranscript` failed because the summary prompt omitted the note. `testSilentRecordingWithTypedNotesStillUsesSummaryTool` returned `noSpeech` and made zero CLI calls instead of one. Both passed after the notes input was added.

The focused processor and lifecycle run passed 57 tests, including existing context and known-word behavior. Further tests cover folder identity across Pause, Stop, another recording, and a changed root. They cover failed saves, held processing until retry, separate notes locking, outside edits, bounded file reads, and explicit summary updates. Summary-only updates preserve the transcript, heard copy, and word-review files. Failed generation keeps the old summary. Edits during generation stay marked as newer than its input snapshot.

Independent review found that invalid notes could fail transcription after the speech models had already finished. A regression test first reproduced `failed(.transcribe)` for oversized notes. The fix preserves the completed transcript and fails the summary step. Repairing the notes retries without another transcription, for both spoken and silent recordings. A notes-only summary failure also remains retryable.

Native text tests exercise insertion, undo, redo, copy, and paste against the saved file. Undo initially changed the text view but left the saved text unchanged. Observing `NSTextStorage` character changes fixes that path. Programmatic renders temporarily detach that delegate so loading text does not save it back. A separate native test verifies the notes button leaves the live transcript available.

The minimum-width regression first measured 476.5 points instead of the requested 460. Wrapping labels now permit horizontal compression and share the content width.

## Native interaction evidence

A live synthetic preview used the real notes window and session, with no production app delegate. Native UI automation typed text and checked `notes.md`, used Command-Z and checked the disk rollback, then used Command-Shift-Z and observed the restored text.

The preview's summary action used a fixed two-second fake delay. During that delay, the update button was disabled. An edit changed the status to say that the running summary used earlier notes. Completion kept the newer notes marked as needing another update and enabled the button again. This verifies native state presentation, not AI summary quality.

The live screenshot showed a Stage Manager thumbnail, so it is not evidence for layout. Layout images come from the actual native views with synthetic text. The capture draws the matching native window background behind each view. It includes light and dark appearances, recording, paused, completed, minimum-size, and failed-save states. The failed-save image includes both recovery buttons at minimum size.

The first render attempts lost their backgrounds during image composition and were rejected. The accepted capture fills an opaque bitmap before drawing the native view. It preserves the light and dark backgrounds and readable button labels.

## Repeat the checks

Create one temporary directory and run the full suite from the repository root.

```sh
task_output=$(mktemp -d "${TMPDIR:-/tmp}/codex-task-XXXXXX")
xcodebuild -project KuKa.xcodeproj -scheme KuKa \
  -destination 'platform=macOS' -derivedDataPath "$task_output/build" \
  test -only-testing:KuKaTests
```

Use the same directory for native tests and images.

```sh
bash scripts/verify-typed-notes.sh "$task_output"
```

The script writes editor images under `notes-ui` and recording-control images under `panel-after`. It runs fake capture and summary adapters. It does not request permissions, record audio, load speech models, or replace an installed app. Xcode writes its test result bundles under `build/Logs/Test`.

Before changing the controls, the existing panel snapshot test captured the baseline with the same synthetic fixtures. The new editor has no earlier equivalent.

After the commands finish, inspect the results and copy any evidence you need. Then remove only this temporary directory.

```sh
rm -rf "$task_output"
```

## Limits

No real recording, permission prompt, model load, or real summary-provider call was used. The tests verify the provider input and invocation, not the provider's response quality. The notes lock coordinates Ku-Ka processes. An outside editor can still change `notes.md` between the read-before-write comparison and the atomic replacement.

Xcode prints existing CoreDevice/CoreSimulator version warnings and Swift actor warnings in Settings code on this Mac. They did not prevent the native macOS tests from running.
