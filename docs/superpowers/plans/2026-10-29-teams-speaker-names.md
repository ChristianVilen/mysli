# Teams speaker names implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox syntax for tracking.

**Goal:** Add opt-in, best-effort Teams names to final remote transcript segments, with conservative fallback.

**Architecture:** A recorder-owned history becomes immutable evidence at Stop. The processing queue passes that value to transcript merging. A bounded read-only AX source supplies observations on a utility task.

**Tech stack:** Swift, AppKit Accessibility, Core Media host clock, XCTest. No new dependency.

**Spec:** `docs/superpowers/specs/2026-10-29-teams-speaker-names-design.md`.

## Global constraints

- User authorizes implementation without live Teams proof. Compatibility remains unverified.
- No live Teams AX, recordings, private transcripts, model downloads, app installs, or UI automation during this task.
- Work only in this existing worktree. No commits, push, publication, merge, new worktrees, or terminal changes.
- Use TDD and fresh bounded implementers followed by independent reviews. One code writer and Xcode process at a time.
- Keep scratch in the parent's single task temporary directory. Show command output directly. Use apply_patch, never Python.
- `teamsSpeakerNamesEnabled` defaults false. Persistent Settings UI belongs to #43.
- Raw observations stay in memory. Preserve Room labels, echo filtering, live draft, context, known words, and action-owner evidence requirements.
- Source limits and matching constants are exactly those in the spec. No unbounded AX traversal, name guesses, or AX writes/actions.
- `KuKa` and `KuKaTests` are synchronized folders. Do not edit project source entries.

## Review focus

1. Delayed scans after Pause/Resume must not bridge a run or its three-second file gap.
2. A name-shaped chat label or another window must never become participant evidence.
3. Queue delay, startup cancellation, quit, and source cancellation must release observation work and not mix meetings.
4. Uncertain/overlapping observations and lost buffered samples must not become positive coverage.
5. Named labels must survive known-word correction and Update Notes without weakening action ownership.

### Task 1: Pure evidence and final transcript labels

**Files:** Create `KuKa/TeamsSpeakerEvidence.swift`, `KuKaTests/TeamsSpeakerEvidenceTests.swift`, `KuKaTests/TranscriptTeamsTests.swift`. Modify `KuKa/MeetingFolder.swift`, `KuKa/Transcript.swift`, `KuKa/MeetingSummarizer.swift`, and relevant summary tests.

**Interfaces produced:**

```swift
struct TeamsSpeakerName: Hashable, Sendable {
    let value: String
    init?(_ raw: String)
}
struct TeamsSpeakerObservation: Equatable, Sendable {
    let began: HostTime
    let ended: HostTime
    let sequence: Int
    let sourceID: String?
    let speaker: TeamsSpeakerName?
}
struct TeamsSpeakerHistory {
    mutating func append(_ sample: TeamsSpeakerObservation, runID: UUID) -> Bool
    func finish(clock: RecordingClock, endingAt: HostTime) -> TeamsSpeakerEvidence
}
struct TeamsSpeakerEvidence: Equatable, Sendable {
    static let empty: Self
    func name(for segment: TranscriptSegment) -> TeamsSpeakerName?
}
```

Add `Speaker.teams(TeamsSpeakerName)`. Render `Name (Teams)` and derive system track. Add default `speakers: TeamsSpeakerEvidence = .empty` after `joinGap` in `Transcript.merge`. Keep historical legend strings unchanged and add named variants. Retain exact pre-feature output when evidence is empty.

- [x] Write failing behavior tests with a buildable minimal stub. Verify expected mismatches before implementation.
- [x] Name validation tests reject reserved/markup/control/oversized forms and preserve ordinary Unicode punctuation.
- [x] Use observations at host times 100.00–100.01, 100.30–100.31, 100.60–100.61, 100.90–100.91 with origin 100. Segment 0.02–0.89 names Aino. At 89% coverage it stays Them. Conflicting names, nil samples, gaps above 750 ms, skipped sequence numbers, different source/run, late samples after Stop, reversed/invalid times, and scans above 150 ms stay Them.
- [x] Pause at 101, resume at 111, and new matching samples after Resume must map to file times starting at 4. No interval may span the pause or resume silence. Test a pause strictly inside two otherwise mappable endpoints. Test cap behavior and no forward extrapolation.
- [x] Transcript tests prove different named speakers do not join, matching names join normally, empty evidence preserves existing output, microphone Room labels/echo behavior remain, and named labels work with correction, quote placement, and summary extraction.
- [x] Summary tests prove UI names do not supply an action owner without transcript evidence. Do not alter CLI arguments, context handling, or relevant-word behavior.
- [x] Run focused Xcode tests, refactor, rerun, and report red/green evidence. Save synthetic before/after transcript examples as test-generated artifacts under `build/task-verification/teams-evidence` for parent inspection, without real data.
- [x] Independent task review before Task 2. No commit per user delivery scope.

### Task 2: Bounded read-only AX source and polling

**Files:** Create `KuKa/TeamsAccessibility.swift`, `KuKa/TeamsSpeakerObserver.swift`, `KuKaTests/TeamsAccessibilityTests.swift`, `KuKaTests/TeamsSpeakerObserverTests.swift`.

**Consumes:** Task 1 `TeamsSpeakerName` and `TeamsSpeakerObservation`.

**Produces:**

```swift
protocol TeamsSpeakerObserving: Sendable {
    func observations() -> AsyncStream<TeamsSpeakerObservation>
}
struct TeamsSpeakerObserver: TeamsSpeakerObserving { /* no work in init */ }
```

Keep AX framework objects inside the adapter. Provide a small injected read interface so fake tree tests exercise the same traversal and attribute-read policy as the real adapter. The observer creates the native adapter on its serial utility task. A snapshot returns an optional name and source context, never raw AX nodes. Use bounded stream buffering with incrementing sequence numbers. Cancellation terminates polling, and permission failure yields uncertainty without prompting.

- [x] Write failing fake AX tests and verify assertion failures before implementing traversal.
- [x] Pin source-based meeting control rules, candidate border classes, ownership of marker and name by one tile, and no `vdi-frame-occlusion`/mute/roster fallback. Test matching ancestor bounds rather than global nearest-name matching.
- [x] Fake trees must cover no Teams, denied/revoked permission, multiple meeting windows, missing controls, chat/captions/shared content traps, self tile, duplicate active tiles, unsupported node shapes, exactly one structurally owned name, raw AX errors, and every scan limit. Assert forbidden text attributes are never read.
- [x] Fake polling tests prove no reads before subscription, serial scans, sequence gaps on buffer loss, nil observations on failure, timestamps bracketing scans, and cancellation cleanup. No real AX even for permission checks.
- [x] Run focused tests, refactor, rerun, and report all unverified selectors. Do not add broad fallback scans to improve synthetic success.
- [x] Independent task review before Task 3. No commit.

### Task 3: Recording, queue, processor, and opt-in integration

**Files:** Create `KuKa/TeamsSpeakerRecording.swift`, `KuKaTests/TeamsSpeakerRecordingTests.swift`, and a focused recorder/pipeline test file as needed. Modify `KuKa/MeetingRecorder.swift`, `KuKa/MeetingNotesController.swift`, `KuKa/MeetingProcessor.swift`, `KuKa/Settings.swift`, `KuKa/AppDelegate.swift`, and affected tests only.

**Consumes:** Tasks 1 and 2 interfaces.

**Produces:** `RecordedMeeting(folder:speakers:)`, recorder `onEnded: ((RecordedMeeting) -> Void)?`, `MeetingProcessor.process(_:speakers:progress:)` with empty evidence default, and `Settings.teamsSpeakerNamesEnabled` get/set using the identical key and false default.

The per-recording collector owns the consumer task and bounded history without triggering UI state changes. It uses new UUID run identity and a host-time lower bound after each Resume. Its `pause`, `resume`, `finish(clock:endingAt:)`, and cancellation paths are synchronous main-actor ownership operations. Native AX reads remain off-main.

- [x] Write failing collector/recorder tests with fake streams and fake capture before integrating.
- [x] Add recorder init injection for `teamsSpeakerNamesEnabled: () -> Bool` default false and `teamsSpeakerObserver: any TeamsSpeakerObserving`. Start observation only after capture starts successfully and opt-in is captured. No missing AX permission may fail audio recording.
- [x] Prove pause/resume, delayed old-stream delivery, Stop, interruption, quit, deinit, startup failure, and cancelled startup release tasks. Do not resume observation after recording ended. Preserve live transcript behavior.
- [x] Pass immutable evidence through the queue. Deduplicate jobs by operation and folder. Recovery/Retry use empty evidence; quit clears queued observation values. Test queue delay, two recordings, and interruption handoff through processor output.
- [x] Processor supplies evidence to merge only during initial transcription. Update Notes uses the heard copy. Verify names remain in both transcripts and summary input, known words affect spoken text only, and existing context/CLI isolation stays intact.
- [x] Add isolated-default tests for false default and round trip, then minimal AppDelegate wiring. No Settings UI, menu item, real defaults write, or permissions prompt.
- [x] Run relevant suites, then full `KuKaTests` suite with real-audio opt-in tests unconfigured. Use worktree-local DerivedData.
- [x] Independent task review, final whole-branch review, and one fix wave if needed. No commit/push/PR/merge.

## Commands and documentation

Focused runs use `xcodebuild -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS' -derivedDataPath build/task-verification test -only-testing:KuKaTests/<RelevantClass>`. Full verification uses `-only-testing:KuKaTests`. Show output directly; no routine log redirection.

The parent updates README, CONTEXT, AGENTS, and task research after implementation. Describe opt-in, AX permission, memory lifetime/recovery fallback, names leaving with the transcript, experimental selectors, and remaining real-call checks. Record exact shared interfaces for #43/#28/#27. Use frontend-pr's before/after principle for generated transcript artifacts; no app view changes are planned.
