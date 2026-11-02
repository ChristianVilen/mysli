# Connect log outputs

> Execute inline with superpowers:executing-plans and TDD. No app startup or UI changes in this stage.

**Goal:** Connect the merged logger to optional daily files and move the existing NSLog calls to privacy-safe logging.
**Architecture:** Each category uses one shared `LogOutput`. It builds a `LogLine` from redacted text, then sends that same message to the unified log and the optional file writer. Tests supply their own output and temporary folder.
**Tech stack:** Swift, OSLog, Foundation, XCTest.
**Spec:** [Log storage design](../specs/2026-10-30-log-storage-design.md), with the scope update below.

## Constraints and scope update

PR #51 is merged and this branch is based on main. The user approved proceeding
with the work it unblocks: both outputs, privacy verification, and the 37-call
migration. PR #49 is still open. Production startup, window activation, the
reader, the log window, and menu controls remain deferred. File output starts
off, and this stage never selects or opens the user's real log folder.

`LogOutput` owns a locked optional `LogFiles` reference. Each write snapshots
that reference, creates one normalized line, and calls the unified-log adapter
and file writer outside the lock. Existing category instances see later file
enabling. The clock, process ID, time zone, and unified-log adapter are injectable.
The native adapter maps info, notice, and error to the corresponding OSLog level,
using the app subsystem, category, and already-redacted message as public text.

Nested `LogMessage` interpolation preserves redaction without marking arbitrary
strings public. `SummaryFailure.logMessage` exposes the tool, kind of failure,
exit status, and searched paths. Launch-error text and stderr stay private.
The existing description remains unchanged for error.md. Update Notes carries
`[SummaryFailure]` to its controller so that it can apply the same rule.

All migrated error descriptions remain private, with numeric error codes public
where the call still has the Error. Fixed labels, paths, date-based folder names,
and framework reason codes can be public. Optional live-transcript diagnostics
use LogMessage from their source so a fixed reason does not become private with
an arbitrary error string. Summary failures get one log line per failed tool.

## Review focus

Private strings must never reach either output, including composed messages.
Both outputs must see the same normalization and level. Enabling files must
affect existing loggers and remain thread-safe. A file failure must not stop the
unified log or recursively use the file output. Summary notifications and
error.md must retain their existing behavior.

## Tasks

- [x] Add failing tests through Log for both outputs, opt-in behavior, metadata,
  all levels, normalized messages, composed privacy, and failed file writes.
- [x] Implement LogOutput and the Log connection; run the focused tests.
- [x] Add failing tests for SummaryFailure log text and the structured Update
  Notes outcome; implement and verify them.
- [x] Migrate the 37 NSLog calls, review public values, and check for remaining
  NSLog calls. Mechanical migrations need no extra test code.
- [x] Update README, AGENTS, and the design to record this stage and pending UI.
- [x] Run the full suite, get an independent review, fix substantive findings,
  and remove task temporary files.

Verification: `xcodebuild -quiet -project KuKa.xcodeproj -scheme KuKa test`.
Focused runs select LogTests, LogOutputTests, MeetingSummarizerTests,
MeetingProcessorNotesTests, and MeetingNotesCheckWordsTests.

## Results

- The first output test run failed because LogOutput and its Log initializer did
  not exist. After implementation, all output and interpolation tests passed.
- The summary tests first failed on the missing logMessage API. Typed failure
  handling and redacted log text then passed with the existing Update Notes tests.
- Full suite: 990 passed, 5 skipped, no failures. The existing Xcode simulator,
  Info.plist, and WordReviewWindowTests QoS warnings remain.
- `rg -n 'NSLog\(' KuKa` has no matches. Public values were reviewed at their
  sources: fixed labels and enum reasons, numbers, framework audio formats,
  paths, and date-based meeting folder names. No error description is public.
- Startup, the reader, and UI remain deferred. The real user log folder is not
  opened by this stage or its tests.
- Independent review approved the scoped changes with no findings. The future
  startup failure callback must bypass file output; this remains part of the
  deferred startup work. Temporary build files were removed. This stage is
  complete.
