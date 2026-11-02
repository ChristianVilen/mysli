# Log storage implementation plan

> Execute inline with superpowers:executing-plans. Use red-green-refactor for each task.

**Goal:** Build the independent storage and filtering parts of the log viewer.
**Architecture:** Immutable log lines and filters, with one queued file owner.
**Tech stack:** Swift, Foundation, Darwin, XCTest.
**Spec:** [Log storage design](../specs/2026-10-30-log-storage-design.md).

## Constraints

Do not change AppDelegate, StatusMenu, or #51's logger yet. No production file
output is enabled. Tests use temporary folders. Folder mode 0700, file mode
0600, retention 14 days, storage cap 20,000,000 bytes excluding today's file
from eviction, display cap 5,000 lines. No new dependencies or project entries.

## Review focus

Test daylight saving offsets, Unicode and embedded newlines, strict file-name
ownership including symlinks, deletion followed by appending, and filtering
before the display cap. Report file I/O errors without recursive logging.

## Tasks

### 1. Log lines

Files: `KuKa/LogLine.swift`, `KuKaTests/LogLineTests.swift`.
Interface: `LogLine(date:processID:level:category:message:timeZone:)`,
`formatted`, and `init?(parsing:)`; `LogLevel` has info, notice, error.

- [x] Write and run failing tests for exact formatting, parsing, offsets,
  line breaks, Unicode truncation, and malformed lines.
- [x] Implement and run the focused tests to green.

### 2. Daily files

Files: `KuKa/LogFiles.swift`, `KuKaTests/LogFilesTests.swift`.
Interface: explicit folder/clock/calendar/error handler; queued `append(_:)`,
async `deleteAll()` and `flush()`; strict daily-name parsing shared with the
future reader. The clock drives startup cleanup; each line owns its timestamp.

- [x] Write and run failing tests for file content and permissions, midnight,
  calendar retention boundaries, storage cap, deletion, recreation, unrelated
  entries, concurrent writers, and I/O failure reporting.
- [x] Implement and run the focused tests to green.

### 3. Viewer filtering

Files: `KuKa/LogFilter.swift`, `KuKaTests/LogFilterTests.swift`.
Interface: `LogRow(text:day:)`, `LogRange`, and `LogFilter.rows(_:now:launchDate:processID:calendar:)`.

- [x] Write and run failing tests for the four ranges, launch PID/time,
  category, errors, unknown rows, stable ordering, and the 5,000-row limit.
- [x] Implement and run the focused tests to green.

### 4. Review and handoff

- [x] Update README and AGENTS with implemented components and deferred wiring.
- [x] Run the complete Xcode test suite and inspect the diff.
- [x] Obtain an independent code review and fix substantive findings.
- [x] Record results here and remove this task's temporary build files.

Verification command: `xcodebuild -quiet -project KuKa.xcodeproj -scheme KuKa test`.
Focused runs add `-only-testing:KuKaTests/LogLineTests` (or the other class).

## Results and decisions

- Privacy interpolation stays with PR #51. This stage consumes already-redacted
  text; the two-output privacy test belongs to the integration stage.
- Use 20 MB as 20,000,000 bytes and Last 7 days as calendar days including today.
- Initial red runs failed on missing types. The first implemented parser also
  failed the multiline rejection test. An explicit newline check fixed it.
- Focused run: 24 passed, no failures. Full run: 900 passed, 5 skipped, no failures.
  Xcode reports existing simulator/plugin and Info.plist warnings. The full run
  also reports a QoS warning in WordReviewWindowTests.
- Independent review found one issue: four Foundation newline characters were
  not escaped, so the parser rejected those formatted messages. The extended
  line-break test failed before the fix. Formatting now uses the same newline
  set as parsing, with CRLF counted once.
- A further file test confirms that deleting through a symlinked root fails and
  preserves the target files. It passed without a production change because
  Foundation already rejects that directory listing.
- Review excluded privacy integration, startup, reader performance, and the UI.
  These remain separate integration work as agreed with the user.
- Final full suite after the newline fix and added file test: 901 passed,
  5 skipped, no failures. All 25 logging tests pass. Temporary build results
  and review probes were removed. App integration remains pending on `log-viewer`.
