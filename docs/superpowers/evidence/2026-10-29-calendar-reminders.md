# Calendar reminder synthetic evidence

`CalendarNativeTests.testSyntheticBeforeAfterEvidenceUsesRealRequestsAndGeneratedDocuments` creates actual `UNNotificationRequest` values through an injected center and writes real summary and transcript files in a temporary meeting folder. Its retained XCTest attachment is named `calendar-reminder-synthetic-evidence`. These are request and document values, not native banner screenshots.

## Requests

Before the feature, Ku-Ka had no calendar requests or categories. The red adapter run returned no request. After implementation, the captured Start request contains these values.

```text
Identifier: calendar-recording.11111111-1111-1111-1111-111111111111
Category: calendar-recording.start
Title: Planning
Body: Record this calendar meeting?
User info: calendarToken = 11111111-1111-1111-1111-111111111111
Trigger: nil
Action: Start Recording
```

The captured End request contains these values.

```text
Identifier: calendar-recording.22222222-2222-2222-2222-222222222222
Category: calendar-recording.end
Title: Planning
Body: The calendar meeting has ended.
User info: calendarToken = 22222222-2222-2222-2222-222222222222
Trigger: nil
Actions: Stop Recording, Continue Recording
```

The native request test asserts categories, action labels, immediate triggers, and token-only data. A default Start click decodes to dismissal. A default End click shows the controls. Unknown actions and malformed tokens have no calendar action.

## Recording menu

The unchanged manual recording test asserts `● Recording · 0:00`. The new title test asserts `● Recording · 0:00 · Planning`, then `Paused · 0:10 · Planning` after ten synthetic seconds. The long-title test asserts a 48-character suffix ending in an ellipsis, with all 120 title characters in its tooltip and accessibility label. No live menu was opened through UI automation.

## Generated notes

Before title metadata is set, the generated summary is:

```markdown
# Meeting on 2026-10-23 at 14:02

Ship on Friday.
```

After `saveDisplayTitle("Planning")`, the written summary is:

```markdown
# Planning

Ship on Friday.
```

The written transcript starts with `# Planning`, reports `Duration: 00:01:00`, and names `Synthetic` as its transcriber. Empty synthetic segments produce `No speech was detected.` The dated folder name is unchanged. Existing title tests cover reconstruction, Markdown escaping, and keeping the heading out of spoken summary content. No model, CLI, private transcript, or capture was used.

## Pending native checks

Native banners and VoiceOver require actual notification delivery and remain unverified. Calendar grants, real recurrence and provider behavior, sleep and wake, and the sibling Settings UI remain manual checks. Fixtures do not prove these platform behaviors.

## Test results and review

The final implementation is `2a81939`, based on `5ee18b6`. The full unit run passed 852 tests, skipped five opt-in checks, and failed none. The parent read the result bundle directly at `build/task-verification/Logs/Test/Test-KuKa-2026.10.29_17-11-20-+0200.xcresult`.

The five skips cover panel pictures, two live-audio checks, real Whisper audio, and real SpeakerKit audio. The run cleared both raw and `TEST_RUNNER_` opt-in variables. Model-free tests remained enabled. No real calendar, recording, notification delivery, private transcript, or model download was used.

Xcode printed CoreDevice, CoreSimulator, duplicate-destination, and Info.plist build warnings. The full result also contains a QoS priority-inversion warning in unchanged `WordReviewWindowTests.swift`. This run has no baseline evidence that classifies that runtime warning as pre-existing.

| Change | Failing-first evidence | Passing result |
| --- | --- | --- |
| Recording session and title metadata, `80f0234` | Explicit Start returned nil, late permission completion resumed recording after shutdown, and recovered titles stayed date-based. | 134 focused tests passed. |
| Reminder decisions, `d378c48` | Missing requests and deadlines, repeated end banners after a title edit, and a missing end timer after Start. | 55 focused tests passed. |
| Concurrent refresh fix, `744578f` | An unchanged refresh left the end timer nil after accepted Start. | 56 calendar and recorder tests passed. |
| Native adapters and wiring, `2a81939` | Missing native requests, unsafe cross-account identity transfer, and response completion before its action finished. | 85 focused tests passed, followed by the full suite above. |

Independent task reviews approved all three tasks. The controller review found the concurrent refresh race, which a separate worker fixed and another reviewer approved. The final whole-branch review by `gpt-6-astra` approved `5ee18b6..2a81939` with no Critical or Important findings. Added-comment reviews found no new code comments.

One Minor coverage gap remains. Driver restart and AppDelegate startup ordering have no direct regression test. Review found no defect in their ordering or resource replacement. Add that coverage when this wiring changes.

The decision-trail review used `gpt-6-sol`. Its handoff points are preserved here: #43 owns the Settings switch, native checks remain pending, warnings and skips must stay visible, and app-running and provider-identity limits remain part of the contract. App-owned reminders can miss starts during a long sleep or while Ku-Ka is quit. An uncertain provider identity loses its association instead of guessing which event to use.

The implementation used the existing worktree and serial code workers. Routine design choices proceeded under the user's delegation. No sibling branch was merged, and no push, PR publication, app installation, or issue closure was performed.

## Judo refactor verification

The judo refactor starts at `0b609fd`. B1 uses one typed offer, one validating or associated recording link, and one explicit end-reminder state. The controller grows from 304 to 332 lines. It removes dictionary scans and paired link clearing, but does not reduce the total line count. S1 places pending-add cancellation and failed-add cleanup in the native notification adapter. C1 requires an explicit provider source when constructing calendar fields.

Before edits, the unchanged calendar suites passed 43 tests. B1 passed those same behavior tests, including concurrent unchanged refresh and deleted-event post-start validation. The new partial-native-add failure test failed before cleanup changed because pending and delivered request identifiers remained. After cleanup, 45 calendar tests passed. Preparation cancellation and controller disable also exercise the actual adapter through an injected center. The final focused calendar, recorder, and notifier run passed 77 tests.

The full unit run passed 854 tests, skipped five opt-in checks, and failed none. Its result bundle is `build/task-verification/Logs/Test/Test-KuKa-2026.10.29_17-44-21-+0200.xcresult`. Both raw and `TEST_RUNNER_` real-service opt-ins were unset. No real calendar, notification delivery, capture, private transcript, or model access was used.

Xcode again printed CoreDevice, CoreSimulator, duplicate-destination, and Info.plist warnings. The full result contains a QoS priority-inversion warning in unchanged `WordReviewWindowTests.swift`. Its cause remains unclassified. The native checks listed above remain pending.

The final mechanical cleanup in `ffdaf35` names the notification boundary `cancel(tokens:)` and removes its redundant comment. Native removal closures and method behavior are unchanged. All 77 focused calendar, recorder, and notifier tests passed after this rename, with no skips, failures, or runtime warnings. The parent read `build/task-verification/Logs/Test/Test-KuKa-2026.10.29_17-51-34-+0200.xcresult` directly. The full suite above ran before this naming-only change and was not repeated.

Independent task review approved B1, S1, and C1. Final review by `gpt-6-astra` approved `0b609fd..ffdaf35` with no findings. The review checked that the explicit states reduce reasoning about invalid combinations, that notification cleanup has one owner, and that event/session checks, paused behavior, concurrent refresh, and duplicate suppression remain intact. No new code comments remain. The parent also corrected the exact cancellation name in the handoff record. This work stays local.
