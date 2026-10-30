# Open-source references for Teams speaker names

The user later authorized best-effort implementation without live proof. See the [design](../specs/2026-10-29-teams-speaker-names-design.md). The source findings below are still unverified against the installed Teams app.

Checked on 2026-10-29 with `gh api`. These are source-code observations, not results from a Teams call on this Mac. The user confirmed that no suitable call is active. No third-party app was installed, built, or run.

## Most relevant implementation

[Salesforce Thread](https://github.com/salesforce-misc/thread) has the closest implementation to issue #41. At commit `730cab97a3a32ffb48501527183e689c850d5c18`, its [SpeakerVisionMonitor.swift](https://github.com/salesforce-misc/thread/blob/730cab97a3a32ffb48501527183e689c850d5c18/Thread/SpeakerVisionMonitor.swift) contains these Teams-specific rules:

- Recognize the desktop bundle `com.microsoft.teams2`.
- Read `AXDOMClassList`. Candidate speaker classes include `frwhdur`, `f578s74`, `f4mjgsl`, `f1xul6tz`, `fj20gam`, `f3ve9t9`, and `vdi-frame-occlusion`.
- Poll every 300 ms. Match a highlighted element's bottom-left corner to a nearby `AXStaticText` name, within 300 pixels.
- Store timestamped observations and choose a name by weighted votes over a transcript interval.

The source comments say a debug call probe found the classes. They also warn that `vdi-frame-occlusion` can reflect video rendering. The geometry match and name-text filter are heuristics. This source does not establish their accuracy for our Teams version.

The scan writes `AXManualAccessibility = true` and scans multiple host windows. For a native Teams host, it accepts any web area. Those choices do not satisfy our read-only, selected-meeting scope. Do not reuse that scan unchanged. The file carries an Apache-2.0 license header.

Thread also includes [MeetAccessibilityProbe.swift](https://github.com/salesforce-misc/thread/blob/730cab97a3a32ffb48501527183e689c850d5c18/Thread/MeetAccessibilityProbe.swift). Its `watch` mode samples changing DOM classes while participants take turns. This gives us a useful experiment to repeat with a narrower reader. The supplied diagnostic writes dumps and changes AX flags, so it must not run under our current authorization. The path search and single squashed file-history entry did not supply a captured Teams fixture. The comments about discovery remain author-reported evidence.

## Other projects

| Project | Source inspected | Relevance and limit |
| --- | --- | --- |
| [Meeting Transcriber](https://github.com/pasrom/meeting-transcriber) | [ParticipantReader.swift](https://github.com/pasrom/meeting-transcriber/blob/1f49b7b8c1ba6957909b3ee21c206282ac91a1c2/app/MeetingTranscriber/Sources/ParticipantReader.swift) | Reads Teams roster names. Tries `roster-list`, `people-pane`, `participant-list`, and `roster-container`, then generic list containers and window-title parsing. This reader has no active-speaking state or timestamped speaker timeline. |
| [Anarlog, formerly Hyprnote](https://github.com/fastrepl/anarlog) | [Meeting AX types](https://github.com/fastrepl/anarlog/blob/a7dadfbb9477177723cab1e140ae06b4e868ecc5/crates/detect/src/meeting_ax/types.rs) and [probe example](https://github.com/fastrepl/anarlog/blob/a7dadfbb9477177723cab1e140ae06b4e868ecc5/crates/detect/examples/meeting_ax_probe.rs) | Its inspected API reports active calls, platform, permission, window title, and screen sharing. These types expose no active-speaker name. The example also captures chat messages, so it is outside this task's probe scope. This was a targeted inspection, not proof that the entire repository lacks speaker attribution. |

Meeting Transcriber's [ParticipantReaderTests.swift](https://github.com/pasrom/meeting-transcriber/blob/1f49b7b8c1ba6957909b3ee21c206282ac91a1c2/app/MeetingTranscriber/Tests/ParticipantReaderTests.swift) tests name filtering using string arrays. Even the test named `testRealWorldTeamsRoster` supplies a literal array. These tests do not exercise a live AX tree or prove a speaking signal. Broad roster and title fallbacks would also need tighter scoping for Ku-Ka.

The implementation phase also inspected Anarlog's [node.rs](https://github.com/fastrepl/anarlog/blob/a7dadfbb9477177723cab1e140ae06b4e868ecc5/crates/detect/src/meeting_ax/node.rs). Its Teams call checks use a visible enabled `Hang up` control, or `Leave` plus a meeting-surface label. `Meeting controls` and `Calling controls` are two of those labels. These give Ku-Ka source-based control strings to try. Ku-Ka's narrower toolbar scope is its own privacy choice, not a verified observation of Teams.

## Consequence for issue #41

Thread gives us concrete attributes and candidate classes to inspect. It makes a targeted live experiment more useful, but it does not establish live compatibility. For a later check, use the [prepared read-only probe](2026-10-29-teams-ax-feasibility.md). Check actual names, class changes during speech and silence, overlap, and the relationship between each indicator and its participant.

Do not import Thread's pixel-distance threshold, voting thresholds, name filters, or AX flag writes as Ku-Ka requirements. Do not infer an action owner from speaker identity alone. If the read-only tree is insufficient, record that result and use the `Them` fallback. The implementation must remain explicitly best-effort until a live check supports its assumptions.

## Reproduce the source lookup

These commands read public repository metadata and source, not local Teams data:

```sh
gh api 'repos/salesforce-misc/thread/git/trees/730cab97a3a32ffb48501527183e689c850d5c18?recursive=1' --jq '.tree[].path | select(test("Speaker|AccessibilityProbe"))'
gh api 'repos/salesforce-misc/thread/contents/Thread/SpeakerVisionMonitor.swift?ref=730cab97a3a32ffb48501527183e689c850d5c18' -H 'Accept: application/vnd.github.raw+json'
gh api 'repos/pasrom/meeting-transcriber/contents/app/MeetingTranscriber/Sources/ParticipantReader.swift?ref=1f49b7b8c1ba6957909b3ee21c206282ac91a1c2' -H 'Accept: application/vnd.github.raw+json'
gh api 'repos/fastrepl/anarlog/contents/crates/detect/src/meeting_ax/types.rs?ref=a7dadfbb9477177723cab1e140ae06b4e868ecc5' -H 'Accept: application/vnd.github.raw+json'
```
