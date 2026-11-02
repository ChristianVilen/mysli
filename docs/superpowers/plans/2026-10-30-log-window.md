# Log window implementation plan

> Execute inline with superpowers:executing-plans and TDD. The user approved the handover design and asked to finish the now-unblocked work.

**Goal:** Enable daily logs in production and provide Show Log… in the status menu.
**Architecture:** An actor reads and caches daily files. A retained native window filters its results and polls only while open. AppDelegate supplies the production folder, launch time, shared writer, and shared window activation.
**Tech stack:** Swift, Foundation, AppKit, XCTest.
**Spec:** [Log storage design](../specs/2026-10-30-log-storage-design.md) and the window contract below.

## Window contract

- Show Log… comes immediately after Permissions… and brings the same window forward on repeated use.
- Ku-Ka Log is a normal, resizable window, initially 1000 by 600 points. Use native controls and a selectable, read-only monospaced text view with horizontal scrolling.
- Range: This launch, Today, Last 7 days, Everything kept. Category: All followed by the logger's categories. Level: All, Errors only.
- Copy All and Save… use the displayed text. Save uses a native save sheet.
- Delete All Logs asks “Delete all Ku-Ka logs? This can't be undone.” with Delete and Cancel. Cancel and closing the alert delete nothing. File errors remain visible in the window.
- Cmd+F opens the text view's native find bar. Shared OrdinaryWindowActivation keeps other open app windows active when this one closes.
- Read off the main actor every two seconds while open. Cache by file size, modification time, and file identity. Refreshes must not overwrite newer filters or a closed window. Deletion invalidates in-flight reads.
- Follow new text only at the bottom. Preserve scroll position and selection on updates while the user reads older text. Identical results do not replace text.
- Existing LogFilter applies filters before the 5,000-row cap. No log viewer state changes log retention.
- Production writes to ~/Library/Logs/Ku-Ka/. XCTest and Settings preview do not instantiate AppDelegate. File-output failures go only to unified logging.

## Files and interfaces

- `LogFileReader.swift`: `LogReading.rows(in:) async throws -> [LogRow]`; `LogFileReader` actor with an explicit folder and injectable file load for cache tests. Ignore unrelated files and symlinks. Return an empty list for a missing directory, and surface read failures.
- `LogFilter.swift`: a date interval for each range so the reader can skip unrelated days.
- `LogWindowController.swift`: owns the native window, controls, refresh lifetime, shared activation, and injected copy/save/confirm/delete actions.
- `Log.swift`: one ordered category list for the selector.
- `LogOutput.swift`: report file-write failures to unified logging only.
- `AppDelegate.swift`: enable the writer at production launch, record launch time, own the reader/window, and connect the menu callback.
- `StatusMenu.swift`: Show Log… and callback.
- Corresponding XCTest files plus README and AGENTS updates.

## Review focus

Test stale reads after a filter change, close, and delete; replacement of a file
with the same size; malformed rows; shared activation with another window; and
save/copy capturing the displayed text. Check that diagnostics for a failed file
writer cannot recursively write to the same file.

## Tasks

- [x] Add failing reader tests, implement cached background reads and date intervals, and verify them.
- [x] Add failing window tests for controls, refresh lifetime, copy/save/delete, following, find, and shared activation; implement the native window and verify.
- [x] Add failing menu and file-failure tests, connect startup, and verify integration.
- [x] Render and inspect synthetic log states in light and dark appearances. There is no old log window to capture. Controller tests exercise the actual controls and find action.
- [ ] Complete a live keyboard, native-sheet, and VoiceOver walkthrough. Blocked by the native computer-use bridge, which failed startup twice. AppKit view captures omit parts of system-control rendering on this machine, so they are not complete visual evidence.
- [x] Update current docs, run the complete suite, get an independent review, and fix substantive findings.

## Validation

Use `xcodebuild -quiet -project KuKa.xcodeproj -scheme KuKa test`, with
`-only-testing:KuKaTests/<class>` for red-green cycles. Use an isolated native
preview compiled from the actual window sources for visual and interaction QA,
without starting the production AppDelegate or reading real log files.

## Results

- Reader and window tests were added before implementation. Initial red runs
  failed on missing types and APIs. Subsequent assertions caught launch-time
  precision, singular line count, stale forced-follow state, and cancellation
  at the read boundary; all now pass.
- Independent review found two medium issues: selection/scroll movement when
  the display cap removes a prefix, and missing shutdown drain. Tests reproduced
  the cap issue and the absent drain API before the fixes. The window now adjusts
  offsets by retained lines; shutdown drains accepted writes for up to two seconds.
- Full suite after fixes: 1,035 passed, 6 skipped, no failures. The extra skip is
  the opt-in snapshot test, which passed in a separate snapshot run. Existing
  Xcode simulator, Settings actor-isolation, Info.plist, and WordReviewWindowTests
  QoS warnings remain. Bounded shutdown-drain tests also report waiting across
  QoS levels, as they deliberately wait for the utility writer.
- The isolated native preview compiled and opened with synthetic files. The CUA
  native bridge failed twice. It was closed without touching the installed app
  or real log files. Native controller tests verify find-bar opening, copy/save
  text, deletion confirmation, errors, shared activation, polling, and selection.
- Two implementation comments remain: the first explains rounding launch time
  to stored timestamp precision; the second explains the linear suffix matcher
  needed to preserve repeated lines at the display cap. The existing privacy
  and queue-ownership comments remain because they document safety boundaries.
- Implementation is complete. Manual QA above remains pending.
- Final cache-test fixture now pins an exact whole-second modification time so
  same-size replacement is verified independently of timestamp precision. All
  five reader tests passed again. Temporary builds, previews, and captures were removed.
