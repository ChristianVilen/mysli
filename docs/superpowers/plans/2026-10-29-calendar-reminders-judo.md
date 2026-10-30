# Calendar reminder judo fixes

The user approved this plan after the review of `5ee18b6..0b609fd`. The starting commit is `0b609fd`. This is a behavior-preserving refactor of task #28, not a new feature.

## Contract

Keep the behavior in `docs/superpowers/specs/2026-10-29-calendar-reminders-design.md` and `docs/calendar-recording-reminders.md`. In particular, preserve exact event reads, generation checks, recording session checks, double-click suppression, the pending-start refresh race fix, overlap receipts, and paused Stop/Continue. Preserve public Settings/controller entry points and dated meeting-folder identity.

Use only this existing worktree. The parent stays user-facing. Run one code worker at a time. Do not use extra worktrees or terminal windows, change sibling work, push, merge, publish a PR, install an app, or close an issue. Use apply_patch, never Python. No real calendar, notification delivery, capture, private transcript, or model access. Tests use injected boundaries and isolated defaults.

TDD remains approved. Run the existing behavioral tests before changing structure. Preserve their assertions through refactoring. For uncovered contract behavior, write the failing test before its implementation. Do not introduce tests that inspect private state shapes.

## Structure and ownership

- The controller owns one optional typed offer. Its Start or End kind carries the required event and, for End, the session ID. There is no reminder dictionary.
- One recording-link state distinguishes a link being validated from an established association. A single end-reminder state distinguishes waiting, offered at a deadline, and continued. There are no independently mutable pending and active association optionals.
- The notification adapter owns cancellation of pending adds and cleanup of failed adds. Removing a token prevents a pending add from leaving that request visible when it completes. The controller owns action validity and calls removal when its offer is invalidated.
- `CalendarEventFields` requires the provider source in its initializer. Only test factories supply `"synthetic"`.

The approved shape replaces another design round. The earlier investigation already traced the affected flow. The baseline tests below verify that its behavior remains current.

## Throughput checkpoint

- Blocking first steps: verify a clean base and run the focused behavior suite before edits.
- Independent workstreams: one cohesive implementation owner handles B1, S1, and C1 in order. Independent review follows the commits.
- Shared mutable state: source and tests are owned by that worker until its report. The parent writes only this plan and task records during implementation.
- Smallest safe decomposition: keep all three fixes with one owner because B1 and S1 both change the controller's notification lifetime. Keep one verified commit per finding where practical.

### Task 1: Apply B1, S1, and C1

**Owned production files:** `KuKa/CalendarReminderController.swift`, `KuKa/CalendarOccurrence.swift`, `KuKa/CalendarReminderNotifications.swift`, and `KuKa/EventKitCalendarSource.swift`. Add no framework layer or state-machine package. A small private type in these files is sufficient.

**Owned tests:** `KuKaTests/CalendarReminderTests.swift`, `KuKaTests/CalendarNativeTests.swift`, and a shared test support file only if the actual notification adapter needs shared fake-center calls. Keep real adapters under test and replace their external calls. Do not weaken assertions to match a fake.

**Owned documentation:** minimal updates to `AGENTS.md`, `docs/calendar-recording-reminders.md`, the current design, this plan, and the evidence record. Preserve historical verification results and append new results.

- [x] Run CalendarReminderTests and CalendarNativeTests against the unchanged base. Record the count and relevant warnings.
- [x] B1: replace the dictionary with one typed offer. Replace pending/active link records with one explicit state. Replace continued/offered-date combinations with one end-reminder state. Delete the collection scans and paired clearing paths. Keep token-specific stale-completion checks so an old failure cannot clear a newer offer.
- [x] Run the focused behavior tests after B1, including unchanged-refresh and deleted-event post-start races. Commit the verified B1 change.
- [x] S1: put the pending-add cancellation guarantee in `CalendarReminderNotifying` and its native adapter. Remove duplicate post-completion cleanup and the controller's `post` generation parameter, while retaining outer lifecycle checks. Give failed native adds the cleanup formerly provided by the controller.
- [x] Verify cancellation during native preparation, cancellation during native add, and failure after a partial add through the actual adapter with an injected center. Verify controller disable through that same adapter. Add failing coverage before implementing an uncovered cleanup path. Keep action-token validity in the controller.
- [x] Run focused tests and commit S1.
- [x] C1: require `source: String` in CalendarEventFields initialization, pass the real provider source in the native mapping, and migrate every test factory/caller. Run native identity tests and commit C1.
- [x] Update affected guidance, state the structural change per finding, and run the full unit suite with opt-in real-service variables cleared. Record the result and limitations. Self-review with deslop.
- [x] Obtain independent task and final reviews. Resolve findings before delivery, then remove task scratch files and leave the branch local.

## Verification commands

Use `xcodebuild -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS' -derivedDataPath build/task-verification test` with `-only-testing:KuKaTests/CalendarReminderTests` and `-only-testing:KuKaTests/CalendarNativeTests` while iterating. Include recorder and notification tests for the final focused check. Show output directly; `-quiet` is allowed.

For the full unit run, unset raw and `TEST_RUNNER_` forms of `KUKA_MEETING_AUDIO`, `KUKA_LIVE_AUDIO`, `KUKA_SPEAKER_MODEL`, `KUKA_SPEAKER_MODELS`, `KUKA_WHISPER_MODELS`, `KUKA_TRANSCRIPT_OUT`, and `KUKA_PANEL_SNAPSHOTS`. Do not print their values. Use `-only-testing:KuKaTests` for the full unit target. No native manual checks are authorized by this refactor.
