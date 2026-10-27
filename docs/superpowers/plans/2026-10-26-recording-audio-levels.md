# Recording audio levels implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Show microphone and Mac audio meters in the meeting recording menu.

**Architecture:** Measure the converted audio on its existing queue. The active recording exposes timestamped scalar snapshots. The controller reads them only while its menu is visible.

**Tech Stack:** Swift 5 language mode, AppKit, AVFAudio, ScreenCaptureKit, XCTest, macOS 26+.

**Spec:** `docs/superpowers/specs/2026-10-26-recording-audio-levels-design.md`.

## Global constraints

- Use TDD. Observe the expected failing assertions before implementing each behavior.
- Keep PCM and file writes on the existing sample queue. Never send audio buffers to the main actor.
- The menu refresh interval is 0.1 seconds. A reading at least 0.5 seconds old returns zero. Use monotonic uptime for freshness.
- Map RMS to a fraction with a -60 dB floor and 0 dB ceiling. Native indicators show Microphone and Mac audio.
- Run the UI timer only while recording and the menu is open. Preserve other sections' one-second tick.
- Preserve saved audio, transcript processing, shortcuts, and settings.
- Add no package dependency and no manual entries to the synchronized Xcode project folders.
- Use apply_patch for file edits. Do not use Python. Never add a commit co-author.
- The implementation owner has this worktree exclusively. Do not edit the main checkout or .workmux.yaml.
- Do not commit, push, or open a PR during implementation. The parent presents the concrete diff first.

## Review focus

- Int16.min must not overflow during squaring or absolute-value operations.
- Missing or stopped buffers must not leave a frozen active meter.
- Main-actor reads must not wait for audio-file writes.
- Menu-close dispatch must reach the controller through the MenuSection protocol.
- A stopped or interrupted recording must not leak values into the next recording.

## Throughput checkpoint

- **Blocking first steps.** Baseline test command passed on f23a0ac. Design comparison is complete. The user accepted TDD. Write failing behavior tests before product code.
- **Independent workstreams.** No implementation fan-out. Audio measurement and menu lifetime share the ActiveRecording contract.
- **Shared mutable state.** One implementation owner writes this branch. The audio queue owns meter writes, and readers copy scalar state under a short lock.
- **Smallest safe decomposition.** One complete feature is one task because its capture, controller, and menu lifecycle must agree. An independent reviewer checks the resulting diff.

### Task 1: Add recording audio meters

**Files:** Create the two production files named by the spec and focused tests. Modify MeetingAudioCapture.swift, MeetingNotesController.swift, StatusMenu.swift, test fakes, relevant existing tests, AGENTS.md, and README.md. Add a small reusable native preview command only if required to inspect the real view.

**Interfaces:**

```swift
struct RecordingAudioLevels: Equatable, Sendable {
    let microphone: Double
    let system: Double
    static let silent: RecordingAudioLevels
}
struct RecordingAudioMeter {
    mutating func record(rms: Double, for track: MeetingTrack, at uptime: TimeInterval)
    func levels(at uptime: TimeInterval) -> RecordingAudioLevels
}
// ActiveRecording requirement, implemented by real and fake handles.
@MainActor func audioLevels() -> RecordingAudioLevels
// AudioTrackWriter, optional RMS from successfully written converted frames.
@discardableResult func append(_ sampleBuffer: CMSampleBuffer, timelineStart: CMTime) throws -> Double?
// MenuSection requirement, default no-op for existing sections.
func menuDidClose()
```

- [x] Write and run failing tests for independent microphone and system values, exact stale boundary, silence, known RMS, finite full-scale output, and recovery after stale readings. Use explicit timestamps and literal expectations.
- [x] Implement the pure model and measurement. Run focused tests to green. Use synthetic CMSampleBuffers through AudioTrackWriter and inspect the CAF output to prove the saved samples, format, and padding remain correct.
- [x] Write and run failing tests through the real controller and menu with fake capture handles. Assert actual labeled indicator values, visibility, interruption-before-start-return, stop, restart, freshness, close, and immediate reopen behavior.
- [x] Implement the snapshot method, native meter view, menu item, visible-only common-mode timer, and menu-close forwarding. Invalidate the timer on all exit paths and use weak capture.
- [x] Run focused tests to green, refactor, and run the full suite with `xcodebuild -project KuKa.xcodeproj -scheme KuKa -derivedDataPath /Users/christian.vilen/work/ku-ka/build/audio-levels -destination 'platform=macOS,arch=arm64' test`. Limit output through the tool. Do not redirect routine checks to logs.
- [x] Update README.md and AGENTS.md to describe the actual behavior and ownership. Reconcile any accepted design changes in the existing spec.
- [x] Render and inspect the actual native view in light and dark appearance with silence and distinct track signals. Verify real menu lifecycle using deterministic input without capturing the user's surroundings. Save evidence under the ignored root build directory if useful.
- [x] Report the changed files, red and green evidence, full-suite result, preview command and evidence paths, and remaining limitations to the parent. Leave the branch uncommitted for independent review.

## Parent verification and delivery

- [x] Inspect the diff and native renderings. Run independent comment and code reviews.
- [x] Fix accepted review findings and rerun the checks affected by those fixes.
- [x] Show the concrete result to the user. Request approval only if committing, pushing, or creating the PR still needs it.

Final verification on 2026-10-27 passed with 381 tests passed, one opt-in real-audio test skipped, and zero failures. The parent inspected the live native view and menu with synthetic input. Independent review found no blocking issue. Its adapter-coverage suggestion is covered by a new real-callback test and an observed failing mutation check. The scoped review accepted that test. The user approved a local merge to main on 2026-10-27.
