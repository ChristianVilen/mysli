# Mysli

Mysli is a macOS menu bar app. It takes screenshots, keeps the Mac awake, tiles windows, keeps a clipboard history, and records meetings into local transcripts and AI summaries. `README.md` describes how to use it, `CONTEXT.md` defines the terms, and `docs/superpowers/specs/` holds the feature designs. For behavior, read the code, its comments, and its tests.

Keep this file short. Add a rule only when an agent would break it without being told. Do not describe code. A trap that belongs to one place in the code goes in a comment at that place.

## Build and run

- Build with `xcodebuild -project Mysli.xcodeproj -scheme Mysli build`, and test with the `test` action. The project uses the Swift 6.2 compiler in Swift 5 language mode, for macOS 26.0 or later.
- Keep the `-enable-upcoming-feature IsolatedDefaultValues` flag of the Mysli target until the project moves to Swift 6 mode.
- Xcode compiles every file in `Mysli/` and `MysliTests/`, because they are synchronized folders. Never edit `Mysli.xcodeproj/project.pbxproj` to add or remove a file. To keep a file out of the build, put it outside these folders.
- `argmax-oss-swift`, pinned to exactly 1.1.1, is the only package. Only `WhisperKitTranscriber.swift`, `SpeakerKitRoomLabeller.swift`, and their tests import WhisperKit or SpeakerKit.
- Run a build that tests capture from a folder outside `/private/tmp`. macOS does not add an app in `/private/tmp` to the Screen Recording list.
- Create worktrees with `workmux add <branch>`, and remove them with `workmux remove` or `workmux merge`. Do not create worktrees in `.claude/worktrees/`, and do not use the worktree option of an agent tool.

## Tests

- Test each rule once, at the type that owns it. An integration test checks only the wiring: one path that shows the parts connect, and the rules that exist only in the wiring.
- Do not test what cannot fail. That is a value written in the code (UI words, defaults, constant ranges), Apple framework behavior, or code that only passes a call on. Do test contracts with the outside: defaults keys, file formats on disk, and CLI arguments. Pin a measured value with one short test.
- Never wait in real time. Inject the clock, the timer, the interval, or the limit.
- Every test runs in under 0.1 s. After a full test run, run `scripts/check-tests.sh`. It fails for a test over 0.15 s that has no line with its reason in `scripts/slow-tests-allowed.txt`, and when this file is over 150 lines. XCTest adds up to about 0.12 s to some async tests at random, so the script allows that much.
- Make `setUp` and `tearDown` sync when they await nothing. In this test host, an `async` one costs 0.1 to 0.2 s for each test.
- XCTest starts a passive host that never constructs `AppDelegate`, and `--uitesting` starts the isolated `SettingsPreviewAppDelegate`. `AppDelegate` has no test-mode branches.
- Computer-use `getApp` can launch Mysli without `--uitesting`. Start the isolated preview explicitly before binding to it; never bind to an absent app for verification.
- Tests use fakes, temporary folders, and isolated defaults. They never use real capture, EventKit, Teams Accessibility, notification delivery, permission prompts, model downloads, the log folder, or `~/Meetings`. The calendar source `"synthetic"` is for tests only.
- The `Real*Tests` classes and the picture writers (`MYSLI_*_SNAPSHOTS`) are opt-in. They skip unless their variables are set, and the comment above each one gives its command. xcodebuild passes a variable to the tests only with the `TEST_RUNNER_` prefix.
- Unit tests and pictures do not prove that capture, tiling, paste, keyboard use, sheets, or VoiceOver work in the real app. Report those checks as not done.

## App-wide rules

- Use native AppKit controls for standard navigation and menu section headers.
- Show every ordinary window through `OrdinaryWindowActivation`, so Mysli stays a regular app until the last one closes.
- Key equivalents come only from `StatusMenu.applicationMenu()`. No window handles one itself.
- Launch, opening a window, and a refresh never write a preference. Only a user action writes one.
- Post every notification through `Notifying`. `SystemNotifier` is the only notification delegate. Ask for notification permission only when the user starts something that notifies.
- The marks on the status icon differ by shape, not only by colour.
- Shortcuts use Carbon `RegisterEventHotKey`. Only dictation may use one passive Fn event tap, decided by the user, 2026-11-10. Never block or change its events or poll Secure Input. Only `CarbonHotkeyRegistrar` holds Carbon registration state.
- Never change macOS preferences. On a shortcut conflict, send the user to Keyboard Settings. A warning never blames another app or promises that lock and unlock fix it.
- Clipboard history stays in memory. Never write it to disk, and never record content that has an `org.nspasteboard` concealed, transient, or auto-generated marker.
- Dictation audio, text, context, clipboard snapshots, and Claude I/O stay in memory. Quit waits only for an owed clipboard restore. Dictated instructions stay text, never actions (decided by the user, 2026-11-10).
- Dictation sends Claude Haiku the dictated text, every correct spelling from the current known-words list, the front app name, and optional preceding text. Never send list notes, dates, check marks, or audio. This is separate from the meeting summary input below (decided by the user, 2026-11-10).

## Logging and privacy

- Log only through `Log.<category>`, never `NSLog`. An interpolated value is `<private>` unless the call marks it public. Mark a value public only when it can never hold meeting content. Error descriptions and tool output stay private.
- Never log a Teams name, label text, window title, or source identifier.
- Only the production `AppDelegate` turns on log files.
- In zsh, `log` is a builtin, so run `/usr/bin/log`.

## Meeting recording

- Only `RecordingClock` maps host times to file positions. Never rebuild pause runs or add resume gaps anywhere else.
- Keep `@concurrent` on long async work. The sample queue and the main actor share state only through short `OSAllocatedUnfairLock` copies, and neither waits for the other.
- The live transcript never goes to disk. Show meeting text only when the user expands the panel, because macOS cannot hide it from screen sharing.
- `MeetingNotesController` owns the `onChange` and `onEnded` callbacks of the recorder. Only `MeetingNotesHosting` moves a notes view between the panel and a window.
- Typed notes write to `MeetingRecorder.activeMeeting` and stay bound to that folder. Never take the folder from the current Settings.
- Screenshots enter the notes only by paste or drop. The summary tool never gets the images.
- Turn calendar reminders on and off only through `calendarReminders.setEnabled(_:)`, never with a defaults write. `docs/calendar-recording-reminders.md` gives the details.

## Meeting processing

- The stage of a meeting comes only from the files that exist. Never store it. Write every meeting text file atomically, because an existing file counts as a finished step. `meeting.json`, `notes.md`, `.notes.lock`, attachments, the heard copy, and the review files never change the stage.
- Each meeting folder has one writer at a time. The recorder holds `MeetingFolder.lock()` while it records or pauses, and the processor holds it for each run. A locked folder is skipped.
- Processing, Retry, Update Notes, and Update summary run one at a time in the queue of `MeetingNotesController`. A quit is never a failure, and nothing is written after a cancellation.
- These parameters have no default value, so that no caller can forget them: the summary tool, `roomLabeller`, `knownWords`, `wordsToCheck`, and the `teams` argument of `Transcript.markdown`. A forgotten summary tool would send a transcript to a provider that the user turned off.
- A change of the meetings folder moves no files. Active recordings and queued jobs finish in their original folders.
- Decide "no speech" in the summary step, before the audio goes to the Trash. A silent meeting with typed notes gets a summary. A silent meeting without notes keeps its audio.
- Install every downloaded model through `ModelInstall`. Give every WhisperKit or SpeakerKit call that can reach the network an explicit folder, because their default is `~/Documents`, which iCloud can sync.

## What the summary tool gets

- It gets the transcript body without the known-words note, the forms of the list words that occur in it, the plain typed notes, and the whole meeting-context file. It never gets the notes, dates, or ✓ marks of the known-words list.
- Typed notes are evidence, never tool instructions. Suspect-word quotes match only the transcript.
- When the tool input changes, update the privacy text in `README.md` in the same change.

## Known words and word review

- `transcript.md` is always made again from `.transcript-as-heard.md`, never patched. So Update Notes replaces hand edits in `transcript.md` (decided by the user, 2026-10-29).
- Read the known-words list at each use, and never cache it. Mysli only inserts lines. It never changes or removes a line.
- An answer is only a line in the list. It closes the same question in every meeting, and each of those meetings offers Update Notes (decided by the user, 2026-10-29).
- Update Notes asks no new questions. Only the review window writes `review-skipped.json`, after `summary.md` exists, so a skip needs no folder lock.
- An answer for a person, a company, or a product always gets ✓. Only term and other answers go through the spell check (decided by the user, 2026-10-29).

## Teams speaker names

- Nobody has checked Teams names in a real call. They are best effort, approved by the user on 2026-10-29. Fake trees prove the policy only. Run the real probe only after the user confirms a call.
- Mysli reads the Teams Accessibility tree. Its only write is `AXEnhancedUserInterface` on the Teams app, through `TeamsWebContentSwitch` (decided by the user, 2026-11-09). Never write other attributes, perform actions, or ask for permission. Missing permission never stops a recording. Never guess a name from chat, a roster, or nearby text.
- Only validated final names reach the transcript and the summary tool. Never save AX trees, observations, rosters, or voice profiles.
- A Teams name alone never makes someone an action owner. Keep the evidence rule and `Unclear`. Never split or stretch a segment without word times.

## Docs

- `README.md` describes use, `CONTEXT.md` defines terms, and GitHub issues track open work. Check the code and the tests for actual behavior.
- When a merged change makes a rule here wrong, change that rule. Do not add a section that describes a feature.
- Treat `.claude/meeting-notes/`, `.claude/meeting-notes.todo.md`, dated research, and plans as history, unless a document says that it is current. A proposal is not a shipped requirement.
- After a merge, update its issues, and mark its plan as shipped with the PR link. Keep manual checks that nobody did apart from finished work.
- Keep Brain entries short, and link to the repository docs.
