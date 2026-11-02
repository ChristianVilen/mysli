# Typed meeting notes

Issue #26 adds a separate, resizable notes window to the recording controls. The live transcript remains in its own drawer. Notes stay editable after Stop. An explicit **Update summary** action uses later edits.

## Ownership and interfaces

`MeetingRecorder.activeMeeting` exposes the folder only after capture starts. A `MeetingTypedNotesSession` holds that folder for its entire life. Pause, Stop, a new recording, and a changed meetings root cannot redirect its writes.

`MeetingNotesController.typedNotes(for:)` returns the one editor session for a folder. The session owns the draft, saved text, save error, and a separate `.notes.lock`. It reads recording and summary status from the controller through its context closure. The queue and current job own pending and running status; only completed summary results are stored per meeting. The editor and controller share one summary-update eligibility rule. Accepted edits write `notes.md` atomically and synchronously. A 64 KiB UTF-8 limit bounds each save and summary input. Invalid text and failed writes leave the draft available. The general meeting lock stays with the recorder or processor.

`MeetingNotesController` retains the existing recorder callbacks. Stop with unsaved notes stops audio and holds the `RecordedMeeting`, including Teams evidence, until a successful save. The app asks before quitting with an unsaved draft. Closing an unsaved editor hides and retains it. Closing a saved editor releases its session and notes lock. Reopening reads the saved file. An external change causes a save error instead of overwriting it. **Reload saved notes** requires confirmation before discarding a draft.

The existing queue gains a summary-only job. `MeetingProcessor.updateSummary` reads the saved transcript directly and writes only `summary.md`. It does not apply known words, create a heard copy, or change review files. Failed generation preserves the old summary. Existing **Update Notes** still rebuilds the transcript from the heard copy.

Each summary reads one saved notes snapshot and reports that snapshot to the queue owner before the CLI starts. The editor stays editable during generation. Duplicate update requests are disabled while that meeting has queued or running work. Completion compares the snapshot with current text, so later edits remain visibly excluded until the user requests another update.

## Summary evidence

Typed notes are separate meeting evidence. They may supply explicit decisions and action owners. The prompt must state conflicts with the transcript instead of inventing a resolution. Typed text is data, never tool instructions. Word-review questions and quote matching use only the transcript. Missing or blank notes preserve the existing prompt. A silent recording with nonempty typed notes still calls the summary tool.

`notes.md` is input and never changes `MeetingStage`.

Transcription writes the heard copy and transcript without reading notes. The summary step reads saved notes once and handles notes errors. Before moving audio to the Trash, it checks whether the transcript records silence and the notes are blank. That case writes the no-speech summary and keeps the audio, including after a restart.

## Design alternatives

| Alternative | Assessment |
| --- | --- |
| Folder-bound edit sessions with native windows | Chosen. It fits the existing recorder and queue owners and gives each file one editor. |
| `NSDocument` and `NSDocumentController` | Rejected. Fixed `notes.md` destinations would need Save As and duplicate restrictions. Processing callbacks and accessory-app activation would still need custom ownership. |

Two independent design readers checked the recorder, queue, processor, and native window code. The synthesis keeps one implementation owner because these changes share lifecycle and summary-state rules.

## Throughput checkpoint

- Blocking first steps. Read ownership rules, obtain independent design alternatives, and run a failing test at the processor's public `process` interface.
- Independent workstreams. Design readers can work in parallel. Lifecycle, storage, UI, and queue implementation stay with one owner.
- Shared mutable state. The recorder owns the general folder lock. One notes session owns the separate notes lock. Windows never choose paths from Settings.
- Smallest safe decomposition. Verify summary input first, then editor lifecycle and queue behavior, then native UI and the complete suite.

## Scope

The editor uses plain text and Markdown with native undo, copy, and paste. The menu reopens current and recent notes. This change adds no rich-text framework or general meeting library. Verification uses synthetic recordings and data. Real capture, permission prompts, model loads, and installation over the user's app are outside this change.
