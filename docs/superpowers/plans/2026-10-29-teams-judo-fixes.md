# Teams judo review fixes implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Execute only after the user approves this plan.

**Goal:** Fix B1, B2, and B3 from the judo review without changing observable Teams naming or recording behavior.

**Architecture:** Give AX ownership validation one implementation, keep host-to-file interval projection inside RecordingClock, and store startup identity in the recorder's starting state.

**Tech stack:** Swift, XCTest, existing AX reading interface. No new dependency.

**Spec:** `docs/superpowers/specs/2026-10-29-teams-speaker-names-design.md`, with the structural changes below. These changes replace implementation structure, not the experimental feature's policy.

**Status:** The user approved all three fixes on 2026-10-29. All three are done. Each had an independent review, and a final independent review approved B1–B3 together. The final full unit run passed (881 total, 876 passed, five skipped, zero failures). The changes stay uncommitted. Live Teams compatibility stays unverified. The [verification notes](../research/2026-10-29-teams-speaker-verification.md#structural-review-fixes) have the evidence.

## Global constraints

- Preserve all current uncommitted work in this worktree. No other checkouts, worktrees, terminal windows, commits, push, merge, or publication.
- Keep the opt-in default false, raw evidence in memory, Room labels and echo removal intact, and action ownership dependent on transcript evidence.
- Preserve the existing source selectors, scope restrictions, timeouts, limits, name validation, matching thresholds, and fallback behavior. No broader label reads or new name guesses.
- No live Teams inspection, recordings, real permission prompts, model downloads, app installs, or private transcripts. Tests use fake AX and capture, temporary folders, and isolated defaults.
- Use one implementation worker at a time, with independent review after each finding. The parent remains the user-facing session.
- Use existing tests as the baseline for behavior-preserving refactors. Add missing characterization cases before restructuring. Use red-green-refactor for the new clock API; do not report an already-passing characterization test as red evidence.
- Use `build/task-verification` for Xcode. Show command output directly. Keep scratch in one task-specific temporary directory and remove it at closeout.

## Review focus

1. A rejected or extra marker must still cause ambiguity; filtering invalid tiles too early must not turn uncertainty into a name.
2. AX checks have intentional differences between root owners, toolbar interiors, and tile interiors. Consolidation must preserve those differences and forbidden-read behavior.
3. Zero-duration uncertainty and exact pause/resume endpoints must preserve the current half-open recording-run rules.
4. An old asynchronous startup must neither replace a newer recording nor clear its state, emit an alert, or start another observer.
5. Refactoring must not alter callback counts, cancellation order, transcript output, or the recording clock's audio-frame rounding.

### Task 1: B1. Consolidate AX ownership validation

**Files:** `KuKa/TeamsAccessibility.swift`, `KuKaTests/TeamsAccessibilityTests.swift`.

**Target shape:** Keep the native AX reader and external snapshot/observer interfaces unchanged. Replace the flat-list consumers' repeated parent walks with one private tree/ownership representation built during the existing bounded metadata traversal. Store subtree membership directly, rather than discovering it repeatedly through `isInside`.

The ownership layer produces qualified meeting-control and participant-tile references. It holds the ancestor checks and their intentional scope differences in one place. `snapshot` selects candidates and reads only qualified labels; it does not reconstruct ancestry.

The traversal must retain rejected structural nodes where their presence invalidates a candidate. Count all nominated marker tiles before validating the sole tile. An invalid second marker must not disappear early and make the first one look unambiguous. Keep root-owner checks separate from the narrower rules inside a toolbar or tile, without another set of manual ancestor loops.

- [x] Run `TeamsAccessibilityTests` and `TeamsSpeakerObserverTests` as the unchanged baseline.
- [x] Add missing characterization cases for an invalid second marker, forbidden/self metadata at several ancestor depths, and the intentional differences between toolbar and tile interior roles. Assert the literal name or uncertainty and which labels must remain unread.
- [x] Introduce the private ownership representation and subtree membership while retaining the traversal's node, child, depth, deadline, and cancellation limits.
- [x] Migrate meeting-control and candidate-name decisions to qualified references. Remove the four manual ancestor walks and the repeated `isInside` searches.
- [x] Run the same tests plus `TeamsSpeakerEvidenceTests`. Keep every existing name and forbidden-read assertion unchanged.
- [x] Obtain an independent review of policy parity and structural simplification before B2.

**Acceptance:** A reader finds ancestor ownership rules in one implementation. No new label reads occur, no selector policy changes, and all existing fake-tree behavior remains unchanged. New types must replace condition/traversal duplication rather than wrap it in extra forwarding layers.

### Task 2: B2. Move interval projection into RecordingClock

**Files:** `KuKa/RecordingClock.swift`, `KuKa/TeamsSpeakerEvidence.swift`, `KuKaTests/RecordingClockTests.swift`, `KuKaTests/TeamsSpeakerEvidenceTests.swift`.

**Interfaces produced by RecordingClock:**

```swift
struct FileInterval: Equatable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
}

func fileIntervalInOneRun(from start: HostTime, to end: HostTime) -> FileInterval?
func keptFileIntervals(from start: HostTime, to end: HostTime) -> [FileInterval]
```

The plan first named these `fileInterval` and `fileIntervals`. The pre-commit comment review renamed them, because a one-letter difference hid a different rule.

`FileInterval` is nested in `RecordingClock`. The singular method maps a complete interval only when both endpoints belong to one recording run. The plural method clips an interval into its kept pieces, including supported zero-duration point observations. Both use the existing private `runs` and file-position calculation. Neither exposes the boundary-array representation to Teams.

- [x] Add failing tests for the new API before its implementation, using a buildable minimal stub.
- [x] With origin 100, pause at 101, and resume at 111, assert that 100.2–100.8 maps to 0.2–0.8 and 111–111.3 maps to 4–4.3.
- [x] Assert that complete mapping rejects a pause crossing, including one strictly between otherwise mappable endpoints. Clipped mapping of 100.5–111.5 must return 0.5–1 and 4–4.5.
- [x] Pin point observations at origin, inside a run, at Pause, inside a pause, and at Resume. A point at Pause is excluded; a point at Resume maps after the three-second gap. Also cover an open pause, multiple pauses, reversed intervals, and nonfinite input.
- [x] Implement the methods through `RecordingClock.runs`. Leave `cut` and its sample-frame rounding behavior unchanged.
- [x] Replace Teams' `mapped` and `uncertainty` helpers with calls to the clock API. Delete all interpretation of `clock.boundaries` from `TeamsSpeakerEvidence`.
- [x] Run clock, evidence, transcript, audio-writer, and live-transcript tests. Obtain independent review before B3.

**Acceptance:** RecordingClock alone interprets pause/run structure. Named coverage and uncertain recorded portions match the current literal assertions, including zero-duration observations and pause edges.

### Task 3: B3. Put startup identity in the starting state

**Files:** `KuKa/MeetingRecorder.swift`, `KuKaTests/TeamsSpeakerLifecycleTests.swift`, and `KuKaTests/MeetingRecorderTests.swift` only where coverage requires it.

**Target shape:** Change the private case to `State.starting(id: UUID)`. Derive any identity query from that case. Remove the stored optional `startupID` and its six explicit clearing assignments. Keep public phase, callbacks, and start/stop APIs unchanged.

- [x] Run the existing startup, shutdown, and lifecycle tests as the baseline.
- [x] Add a missing late-failure characterization test. Start a newer recording while an obsolete start is suspended, then fail the obsolete start. Assert that the newer recording remains active, no stale alert is shown, and its observer remains the only active observer.
- [x] Store the attempt ID when entering `.starting`. Check that payload after the permission await and capture-start await and in failure handling.
- [x] Preserve stopping a stale returned capture handle. Transitions to idle or active must discard the attempt ID automatically, without extra cleanup writes.
- [x] Preserve opt-in snapshot timing, collector creation after successful startup, cancellation-before-handoff, and existing panel/callback counts.
- [x] Run `MeetingRecorderTests`, `TeamsSpeakerLifecycleTests`, `TeamsSpeakerRecordingTests`, and `MeetingNotesControllerTests`. Obtain independent review.

**Acceptance:** Startup identity cannot exist outside the starting state. No separate mutable ID or manual ID-clearing assignments remain. The documented #28 integration uses its existing Session ID as this state's payload when the branches are later combined; this work does not merge that branch.

## Final verification and delivery

- [x] Run the full unit suite once after all three fixes:

```sh
xcodebuild -quiet -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS,arch=arm64' -derivedDataPath build/task-verification test -only-testing:KuKaTests
```

- [x] Inspect the result bundle, regenerate/read the synthetic before/after transcripts, and confirm the refactors did not change their content.
- [x] Re-run the structural review against B1–B3. Verify that complexity was removed rather than relocated into wrappers or configurable validators.
- [x] Update AGENTS, the design, and verification/integration notes for the clock API and state-owned startup identity. Preserve the explicit unverified status of live Teams compatibility.
- [x] Report the outcome for each finding ID, tests, remaining checks, and sibling integration conflicts. Leave changes uncommitted and remove this run's scratch files.
