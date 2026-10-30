# Teams speaker-name verification

## Scope and authorization

The user authorized best-effort implementation without live Teams proof on 2026-10-29. The earlier read-only diagnostic remains available. No real Teams AX tree, private meeting transcript, calendar, or recording was inspected during implementation. No app was installed or enabled.

The [design](../specs/2026-10-29-teams-speaker-names-design.md) lists the source assumptions and exact fallback policy. The [plan](../plans/2026-10-29-teams-speaker-names.md) records the implementation boundaries.

## Automated checks

The final full-unit run used:

```sh
xcodebuild -quiet -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS,arch=arm64' -derivedDataPath build/task-verification test -only-testing:KuKaTests
```

The latest run, after the structural review fixes below, has the result bundle `build/task-verification/Logs/Test/Test-KuKa-2026.10.30_09-44-31-+0200.xcresult`. It reports 881 total tests, 876 passed, five skipped, and zero failures. The earlier run before those fixes (`Test-KuKa-2026.10.29_17-51-58-+0200.xcresult`) reported 870 total, 865 passed, five skipped, and zero failures. The parent read each summary with `xcrun xcresulttool get test-results summary`. The skips are the panel-picture test, two real live-transcription tests, the real Whisper-audio test, and the real SpeakerKit room-label test. Their opt-in environment variables were not configured.

Known Xcode CoreDevice/CoreSimulator and Info.plist resource warnings remain. The bundle also contains the existing QoS warning in `WordReviewWindowTests`. These did not fail the build or tests. `git diff --check` passed.

Tests use fake AX, fake capture and transcription, temporary meeting folders, and isolated defaults. Native AX functions have compilation coverage only. Summary tests check the prompt, not a provider's future compliance with it.

## Red-green evidence and review corrections

| Area | Observed failure before implementation or fix | Passing check |
| --- | --- | --- |
| Pure attribution | Returned nil instead of Aino; transcript kept Them instead of distinct names | Evidence and named-transcript suites |
| Conservative matching | A single Bob observation or invalid sequence still permitted Aino; pause-crossing uncertainty failed to veto a name | Literal name and nil assertions |
| Name validation | Unicode line separators and combining marks could bypass required rejection | Unicode scalar regression for all seven forbidden delimiters |
| AX scope | Forbidden toolbar/button text was read; self owners and unknown toolbar owners still produced Ada | Fake trees assert both uncertainty and absence of forbidden reads |
| Polling | Empty sequences instead of `[1, 2, 3]`; cancelled traversal continued reading | Timestamp, cancellation, serial scan, and bounded-buffer tests |
| Collector and recorder | Missing source termination and missing names; a stale capture was not stopped | Fake lifecycle and cancellation suites |
| Queue | Waiting meetings lost their names; quit left Alice in a pending payload | Two-meeting delay and empty-recovery tests |
| Settings and pipeline | Preference was not stored; heard transcript lacked the supported name | Isolated defaults and correction/Update Notes tests |

Core behavior was implemented through failing, buildable tests. Some additional negative cases already passed against that implementation and provide regression coverage. Two mistakes in test fixtures were corrected during iteration: known-word right forms need bold Markdown, and the `agy` prompt is a command argument rather than stdin. Neither was a production failure.

Independent task reviews checked the model, AX adapter, and lifecycle integration. The Unicode delimiter and AX ownership findings were fixed with regressions and independently re-reviewed. The comment review found no added Swift comments to remove. Xcode prunes older result bundles, so not every early red bundle remains on disk.

The final whole-change review by `gpt-6-astra` approved the agreed experimental scope without blocking findings. It directly confirmed the final result bundle and synthetic transcripts. It could not independently revalidate historical red runs whose bundles Xcode had pruned. Live Teams selectors remain unverified. These are the two attention items from the decision-trail review.

Model the Domain shaped the validated name, observation, and immutable evidence values. Separate Before Serializing Shared State kept one recording as the observation owner and one queued job as the evidence owner. Prove It Works kept the tested policy separate from the untested Teams UI assumptions. The user delegated routine implementation decisions, so the parent chose the narrower source profile and default-off preference without another approval checkpoint.

## Structural review fixes

A later structural review found three places where one rule lived in several places. The user approved the [fix plan](../plans/2026-10-29-teams-judo-fixes.md) on 2026-10-29. Each fix keeps the observable behavior.

| Finding | Change | Evidence |
| --- | --- | --- |
| B1. AX ancestry checked by four manual ancestor walks and repeated `isInside` searches | The bounded metadata traversal records each node's inherited ownership facts and subtree range; meeting-control and tile decisions use qualified references | Three characterization tests passed against the old code first. 45 focused tests passed after the change. A scratch differential check ran the old and new policy on 20,000 generated trees (651 with a name) and matched names, source identity, and the order of every metadata and label read |
| B2. Teams evidence rebuilt pause runs from `RecordingClock.boundaries` | `RecordingClock.fileIntervalInOneRun(from:to:)` and `keptFileIntervals(from:to:)`; the two Teams timing helpers are deleted, and `boundaries` is now `private` | The new API tests failed against buildable stubs first. 81 focused tests passed after the change, with points at a Pause and a Resume, open pauses, reversed and nonfinite input, and the unchanged audio cut |
| B3. A stored `startupID` next to the recorder state, with six clearing assignments | `State.starting(id: UUID)`; identity checks read the state | A new test (a newer recording survives an obsolete start's failure with no alert and one observer) passed against the old code first, so it is characterization, not red evidence. 79 focused tests passed after the change. After review, two more tests resolve the obsolete start while the newer one still waits. Both failed when a check of the phase replaced the identity checks, and passed after the restore. 81 focused tests passed |

The synthetic before and after transcripts below were generated again by the full run, and they are byte for byte the same as the copies saved before the fixes. Each fix had an independent review, and a final independent review of all three approved the structure, the behavior, and these notes without blocking findings.

## Before and after output

`TranscriptTeamsTests.testWritesSyntheticBeforeAndAfterExamplesFromTheMergePath` generates these files through the actual merge and Markdown renderer:

- `build/task-verification/teams-evidence/before.md` contains one joined `Them` line.
- `build/task-verification/teams-evidence/after.md` contains separate `Aino (Teams)` and `Bo (Teams)` lines and the new legend.

The parent read both files. They contain synthetic speech only. No app view changed, so the evidence is transcript output rather than UI screenshots.

## Sibling integration contract

- Task #43 can bind its checkbox to `Settings.teamsSpeakerNamesEnabled`. The key has the same name and defaults false. AppDelegate supplies one closure to the recorder. Do not add a second preference or a competing menu toggle.
- Task #28 already has a recorder `Session` identity for title/recording association. This branch keeps the start attempt's identity in the recorder's private state, `State.starting(id: UUID)`, and checks it after the permission and capture awaits and in the failure path. There is no separate stored ID. When combining the branches, make #28's existing Session ID the payload of `.starting` instead of the `UUID`, and do not add a second ID. Preserve the opt-in snapshot, stale-handle stop, and collector creation only after successful startup. Both changes touch `MeetingRecorder`, so this needs a deliberate merge.
- The recorder now sends `RecordedMeeting(folder:speakers:)` through `onEnded`. The processing job deduplicates by operation and folder and calls `MeetingProcessor.process(_:speakers:progress:)`. Recovery and Retry pass `.empty`.
- `Speaker.teams(TeamsSpeakerName)` remains a system-track speaker. Task #27's remote diarization is separate. No voice profile or cross-meeting identity store exists.

No sibling branch was merged or modified. AppDelegate, Settings, recorder startup, and shared documentation are the likely integration conflicts.

## Remaining real-world checks

During a later user-confirmed Teams call, verify the English toolbar labels, AXGroup video-tile shape, static-text name ownership, border classes, self markers, and highlight transitions. Check silence, two speakers taking turns, overlap, sharing, hidden/minimized windows, missing permission, and a permission change. A persistent last-speaker highlight remains a possible wrong-name source. Unsupported layouts can yield only `Them`.

Use the [scoped probe procedure](2026-10-29-teams-ax-feasibility.md). Do not start or join a call, enable AX flags, or read unrelated chats to obtain proof. Fake test success does not establish live compatibility.
