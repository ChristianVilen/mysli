# Calendar reminders implementation plan

> For agentic workers: Use superpowers:subagent-driven-development. Apply TDD with red, green, and refactor for every behavioral change.

**Goal:** Offer safe calendar reminders and retain the selected event title without changing recording or recovery rules.

**Architecture:** One app-owned controller reconciles immutable calendar snapshots and session-specific actions. EventKit and UserNotifications remain behind injected boundaries. The recorder owns session identity and the meeting folder owns title metadata.

**Tech stack:** Swift, AppKit, EventKit, UserNotifications, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-29-calendar-reminders-design.md`.

## Global Constraints

- Work only in the existing calendar-recording-reminders worktree. No additional worktrees, terminal windows, or subagents from workers.
- Do not change real calendars, start recordings, inspect private meeting transcripts, download models, install apps, or run UI automation in parallel with other workers.
- Use fake calendar/AX/capture, temporary meeting folders, isolated defaults, and `build/task-verification` DerivedData.
- Preserve recording clock, 3-second resume silence, recovery, live-draft memory-only behavior, known words, context input, and CLI isolation.
- Titles must not change date-based folder names, canonical URL equality, hashing, or stage discovery.
- Persistent preference presentation belongs to #43. Add no Settings window or preference menu item.
- Keep AppDelegate, Settings, Notifier, transcript, and docs edits small. Do not merge sibling branches.
- Use apply_patch, never Python. Show command output directly. No push, PR publication, merge, app install, or issue closure.

## Review focus

- An old Stop action must not stop a later manual recording. Tasks 1 and 2 test session guards.
- Permission or capture completion after shutdown must not publish an active recording. Task 1 suspends each boundary.
- An event end changed while a reminder is visible must invalidate the old action. Task 2 tests revision changes and new due time.
- Title metadata must not enter summary spoken content or break recovery. Task 1 tests the real folder and fake processor.
- A notification add completing after disable must be removed. Tasks 2 and 3 test controller generation and notification transport completion.

### Task 1: Recording identity and display titles

**Files:** `KuKa/MeetingRecorder.swift`, `KuKa/MeetingFolder.swift`, optional new `KuKa/MeetingTitle.swift`, minimal heading formatter edits in `Transcript.swift` and `MeetingSummarizer.swift`, corresponding tests in `KuKaTests/MeetingRecorderTests.swift`, `MeetingFolderTests.swift`, and processor tests.

**Interfaces:** Provide `startRecording(title: String? = nil) async -> UUID?`, `activeSessionID: UUID?`, `displayTitle: String?`, and `stopRecording(ifSession: UUID)`. Keep existing toggle and Stop for manual callers. Provide `MeetingFolder.saveDisplayTitle(_:) throws` and have `title` prefer validated metadata. Title metadata is `meeting.json`, version 1, normalized single-line text capped at 300 characters, with a bounded 16 KiB read. Missing/bad metadata uses existing dated title.

- [x] Add failing tests for explicit start while busy, stale Stop, paused session identity, and shutdown across both permission and capture suspension. Watch assertion failures before implementation. Minimal compiling declarations may precede an assertion failure, but do not count compilation errors as the red test.
- [x] Implement a session-carrying Starting state and ActiveMeeting. Check the start attempt after each await. A late capture handle after shutdown is stopped and cannot replace a newer session. Preserve any recorded audio for normal recovery. Manual toggle uses the explicit start internally.
- [x] Add failing tests that title metadata survives folder reconstruction, preserves name/equality/stage/discovery, rejects oversized or invalid metadata, and handles newline/Markdown/path-like titles safely.
- [x] Write title metadata under the folder lock before capture. Store one normalized plain title. Escape Markdown heading syntax at heading output, so a title cannot inject extra headings or spoken lines. Keep summary CLI input unchanged.
- [x] Run recorder, folder, transcript, processor, and summary tests. Show output and record red/green evidence. Self-review and commit only task-owned changes, with no co-author.

### Task 2: Calendar reminder decisions and Settings interface

**Files:** New `KuKa/CalendarOccurrence.swift`, `CalendarReminderController.swift`, `CalendarReminderStore.swift` if needed; minimal `KuKa/Settings.swift`; new focused calendar tests. No EventKit or UserNotifications implementation in this task.

**Interfaces:** Consume Task 1 explicit start/session APIs. Define `CalendarEventSource`, `CalendarReminderNotifying`, `CalendarReminderRecording`, and an injected timer/wake boundary. A real recorder conformance may live in the calendar file. Provide `setEnabled(_:) async`, `resume() async`, `refresh() async`, `recorderDidChange()`, `shutDown()`, `status`, and `onStatusChange`. Inject Settings or closures with isolated defaults in tests. Publish concrete adapter signatures in the report for Task 3.

- [x] Add failing behavior tests for start delivery at the event start, two-minute wake grace, action valid until end, eligibility exclusions, one offer across refreshes, restart receipts, edited event, and distinct recurring occurrences.
- [x] Implement one controller-owned typed reminder state. Tokens refer to exact event revisions and session IDs. Prefer one controller over a reducer plus an equivalent mutable state copy. Persist bounded consumed receipts without event titles. Seven-day expiry and 2,048 receipt cap are sufficient.
- [x] Add failing tests for simultaneous and staggered overlap, manual/busy start, paused end, Continue without resume, late Stop after a different recording, changed end, deleted/cancelled/declined event, and read failure. Keep at most one valid start offer visible. Consume new overlapping starts while that offer remains valid.
- [x] Implement guarded actions. Refresh exact event before acting, consume token before awaits, and rely on the recorder's atomic session guards. Stop never toggles. Continue suppresses end reminders for that session.
- [x] Add failing tests for default-off launch, saved enabled launch without prompt, denied/revoked access, disable during permission request, stale async snapshot, and late notification add after disable. Implement generation and cancellation rules.
- [x] Run focused calendar tests and Task 1 recorder tests. Record red/green evidence, exact Settings API, and any design deviations. Self-review and commit only task-owned files.

### Task 3: EventKit, native notification actions, and app wiring

**Files:** New `KuKa/EventKitCalendarSource.swift`, `CalendarReminderNotifications.swift`, optional `CalendarReminderDriver.swift`; small `KuKa/Notifier.swift`, `AppDelegate.swift`, and `Info.plist`; calendar adapter/notification/wiring tests. Update README, CONTEXT, AGENTS and task integration/evidence docs minimally.

**Interfaces:** Implement Task 2 protocols. Keep `SystemNotifier` the only notification delegate. Expose calendar action routing without disturbing open/checkWords. The controller is constructed and resumed outside the existing test-host guard only. #43 calls the exact documented enable/status API, not a defaults-only toggle.

- [x] Add failing tests for EventKit value normalization using synthetic event input and identity across recurring/detached occurrences and nonrecurring time edits. Test authorization mapping without reading the real store. Implement read-only full-access adapter and Calendar usage string.
- [x] Add failing tests for native categories, Start/Stop/Continue action decode, unknown/default/dismiss behavior, feature-only removals, and late completion cleanup. Inject notification-center calls. Never deliver a real notification in tests.
- [x] Implement next-boundary timer plus 60-second safety refresh and EventKit/wake/clock signals. Inject scheduling callbacks for tests. Query 24 hours ahead and associated occurrence safely. Refresh status without requesting access at launch.
- [x] Wire the optional controller in AppDelegate using the existing meetingNotes state callback. Stop watchers at quit. Do not steal recorder callbacks. Test host must not construct/read EventKit or register/post calendar notifications.
- [x] Document the exact #43 integration interface, ownership/conflict list, eligibility, limitations, and real-world checks. Produce synthetic before/after evidence from actual requests and generated notes. Do not describe request fixtures as native screenshots.
- [x] Run focused adapter/notification tests, then the full unit suite once. Report warnings and skipped real-model tests. Self-review and commit owned changes. Parent performs final independent review.

Task 3 passed 85 focused tests and the full model-free unit run passed 852 tests with five opt-in tests skipped. Native banner and VoiceOver checks remain manual. See `docs/calendar-recording-reminders.md` and the synthetic evidence record. Parent independent review remains open.
