# Meeting panel cleanup implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development or superpowers:executing-plans. Track each task below through its failing test and passing verification.

**Goal:** Record timestamped text and screenshot notes while reading a selectable live transcript in one floating native panel.

**Architecture:** Keep `notes.md` authoritative and preserve `MeetingTypedNotesSession` as the save and lock owner. Compose an embeddable native notes view with the existing transcript drawer and retain the notes presentation after Stop. Live and note row timestamps use audio-file positions.

**Tech stack:** Swift, AppKit, ImageIO, XCTest, native `NSGlassEffectView`.

**Spec:** `docs/superpowers/specs/2026-11-03-meeting-panel-cleanup-design.md`.

## Global constraints

- Work in the existing `feat/55-meeting-notes-cleanup` checkout. No worktree.
- Use TDD, as approved by the user. Run synthetic native tests without recording, permission prompts, or model downloads.
- Add screenshots through paste and drop only. No file picker, upload button, or capture button.
- Keep standard macOS notifications. Add no custom reminder UI.
- Preserve existing plain notes, external-edit detection, native undo, failed-save drafts, folder identity, processing holds, and explicit summary updates.
- No manual Xcode source-file registration.

## Review focus

- Stop clears recorder controls after its notice expires. Attached notes must remain editable.
- New recordings must not redirect an older session's edits or attach it below a different live transcript.
- Resume gaps must affect live and note timestamps in the same way as the final transcript.
- Image failures and notes write failures must not produce saved links to missing files or lose a retained draft.
- Incoming live updates must preserve unchanged selected text and never move gray drafts above committed messages.

## Design choice

Independent sketches preferred canonical Markdown entries over JSON plus generated Markdown. One atomic note document retains the existing saved-text comparison and summary snapshots. Entry times distinguish recording file positions, after-recording notes, and undated legacy text. Generated image names are relative to the original meeting folder.

Both sketches preferred composing the existing floating panel over replacing all window ownership. Share the native editor view with the historical-notes host. Keep one view per session because the session currently has one change callback.

## Throughput checkpoint

- Blocking first steps. Read existing ownership, compare independent design sketches, and capture baseline native views. Completed baseline has 56 passing tests.
- Independent workstreams. The root owns live transcript row ordering and timestamps. One implementation owner handles note storage, editor, and panel integration because these share lifecycle interfaces.
- Shared mutable state. Separate file ownership. Serialize Xcode runs in one derived-data directory. Keep one writer per notes session and retain the separate notes lock.
- Smallest safe decomposition. Verify live row behavior, then row and screenshot persistence, then native integration and whole-suite behavior.

## Task 1. Live transcript timeline and draft order

**Files:** `KuKa/LiveTranscript.swift`, `KuKaTests/LiveTranscriptTests.swift`.

**Interface:** `LiveRow.at` becomes an audio-file position. `LiveTranscript.preview(on:)` retains the clock argument for pause rows and lag handling. Committed speech and pause markers retain timeline order; unsettled draft phrases follow committed rows, ordered by start time with system first on ties.

- [x] Change the existing ordering and pause tests to require drafts at the bottom and file-position timestamps. Add an older changing system draft below a newer final microphone line.
- [x] Run the focused tests and observe the expected failures.
- [x] Update preview construction and its documented clock contract.
- [x] Run all `LiveTranscriptTests` and relevant recorder tests.

## Task 2. Timestamped note rows and screenshot files

**Files:** New `KuKa/MeetingNoteEntries.swift` and image import adapter; `KuKa/MeetingTypedNotes.swift`, `KuKa/RecordingClock.swift`, `KuKa/MeetingRecorder.swift`, `KuKa/MeetingNotesController.swift`; focused note and clock tests.

**Interfaces:** `MeetingNoteTime` distinguishes recording position, after-recording, and undated notes. `MeetingNoteEntry` has session-stable identity, time, editable text, and safe relative attachments. `MeetingTypedNotesSession` exposes entry edits and screenshot insertion through its existing save path. The recorder exposes a note position frozen during Pause and including prior resume gaps.

- [x] Add failing public-seam tests for stable creation time, multiline and legacy round trips, folder-bound entries, pause mapping, and after-Stop times.
- [x] Add failing image tests for real PNG persistence, bounded input, invalid data, and retained drafts after external note edits.
- [x] Implement canonical Markdown entries without a second authoritative document. Write immutable PNGs before saving their links, and keep files available for undo and Retry.
- [x] Run note, recorder, clock, lifecycle, and processor tests. Existing plain `edit(_:)` callers retain their behavior.

## Task 3. Shared native notes editor and combined floating host

**Files:** New `KuKa/MeetingTypedNotesView.swift`; `KuKa/MeetingTypedNotesWindow.swift`, `KuKa/MeetingControlsPanel.swift`, `KuKa/MeetingPanelPlacement.swift`, `KuKa/MeetingPanelCopy.swift`, `KuKa/AppDelegate.swift`; native editor and panel tests.

**Interfaces:** `MeetingControlsPanel.showNotes` receives the existing folder-bound session, summary action, and close action. The shared editor owns native editing and undo, save recovery, and paste/drop. Panel presentation distinguishes compact, transcript, and read-and-write. Notes presentation outlives recorder controls.

- [x] Add native tests for embedded notes with live text, editing and native undo, paste and drop, title display, useful minimum sizes, solid accessibility appearance, and post-Stop retention. Some UI tests followed initial implementation; regression failures verified the missing text system, opacity, and reviewed defects.
- [x] Extract the shared editor and wire active notes to the combined panel. Historical notes use a floating host and never replace an active session's change subscription.
- [x] Use native glass on the shell and controls, quiet text surfaces, and native accessibility preferences. Keep Pause and Stop from taking keyboard focus.
- [x] Verify saved edits, summary status, close and reopen behavior, and switching meetings with unsaved drafts.

## Task 4. Selectable transcript and completion checks

**Files:** `KuKa/MeetingTranscriptDrawer.swift`, related native views and tests, `README.md`, `CONTEXT.md`, `AGENTS.md`, current design and verification docs.

**Interfaces:** Render the transcript in a noneditable selectable native text view. Preserve unchanged-prefix selection and scroll position during incoming updates. A selection suspends automatic following. Notes retain their independent scrolling and focus.

- [x] Add failing native tests for copy across messages, selection surviving append, and draft replacement. Preserve transcript scroll position while an editable notes view has focus.
- [x] Implement native selection without making transcription or notes saving depend on window activation.
- [x] Run focused native checks and the full XCTest suite. Inspect matching before and after images in light and dark appearances.
- [x] Run independent review, address correctness findings with regression tests, and update current docs with verified behavior and limits.

Screenshot links are durable note evidence. The current summary providers receive text only. Do not claim that a provider sees image pixels through a Markdown link or change provider permissions as part of this work.
