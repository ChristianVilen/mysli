# Teams Accessibility feasibility check

Later on 2026-10-29, the user authorized best-effort implementation without a live call check. The [implementation design](../specs/2026-10-29-teams-speaker-names-design.md) records that change. The probe results below remain unchanged. No real Teams compatibility result exists.

Status on 2026-10-29: prepared, not run against Teams. The user confirmed that no suitable call is active. Participant names and a changing speaking indicator remain unverified. This is not evidence that Teams lacks either signal.

The original requirement came from [issue #41](https://github.com/ChristianVilen/ku-ka/issues/41), which required a real call check before design. The later user instruction supersedes that prerequisite. The historical floating-panel reference in the issue shipped in #45. The worktree starts at `5ee18b6`, which also includes #46 and #47.

## Prepared diagnostic

[`scripts/teams-ax-probe.swift`](../../../scripts/teams-ax-probe.swift) takes one exact Teams process ID, the exact focused meeting-window title, and an explicit confirmation flag. It never enumerates other apps or windows.

The two modes have different read boundaries:

- `structure` reads the selected node's role and attribute names, plus at most 40 immediate child roles. It does not read their text, descriptions, identifiers, or values. It reads the focused window title only to check the supplied title and does not print it.
- `read` reads one allowlisted attribute of one explicitly selected node. It refuses the window root and text inputs. It does not read descendants. It prints host-clock ticks before and after the attribute read.

Paths contain zero-based child indices separated by periods. They are temporary diagnostic locations, not stable Teams selectors. A changed layout can invalidate them. The operator must establish that a selected node belongs to a participant control before reading its content. If structure alone cannot establish that scope, stop and request a narrower user-identified control. Do not read candidate text across the window to search for names.

Each AX message has a one-second timeout. The tool reports AX error codes separately from refusals. An error does not mean that a speaking indicator is absent. Combined string content is capped at 2,048 UTF-8 bytes before JSON escaping. JSON quotes, delimiters, and escape sequences can make the printed output larger. The tool writes no files, but terminal output can remain in terminal or assistant history. Keep real names out of committed research notes and test fixtures.

There are no Accessibility attribute writes, UI actions, focus changes, screenshots, permission prompts, timers, or recordings. Setting the AX client message timeout is the only AX setter. In particular, the probe does not enable `AXManualAccessibility`.

## Build and check without a call

Run these commands from the repository root. The test executable uses fake AX only.

```sh
probe_tmp=$(mktemp -d "${TMPDIR:-/tmp}/codex-task-XXXXXX")
xcrun swiftc -parse-as-library -module-cache-path "$probe_tmp/module-cache" -D PROBE_TESTS scripts/teams-ax-probe.swift scripts/teams-ax-probe-tests.swift -o "$probe_tmp/probe-tests"
"$probe_tmp/probe-tests"
xcrun swiftc -parse-as-library -module-cache-path "$probe_tmp/module-cache" scripts/teams-ax-probe.swift -o "$probe_tmp/teams-ax-probe"
"$probe_tmp/teams-ax-probe" --help
```

The initial test run reported `0/30 passed` against a nonfunctional stub. The implemented probe reported `30/30 passed`. CLI compilation and `--help` passed. The tests cover request guards, permission refusal, wrong app and window, path limits, structural output without chat text, explicit attribute reads, text-input refusal, output limits, and AX errors. These results establish diagnostic behavior with a fake source, not Teams compatibility. The real AX adapter has compilation coverage only.

Independent task and final reviews found no blocking issue for diagnostic preparation. Their test improvements were applied and reviewed again. Removing the attribute allowlist in a temporary copy made `disallowed attribute` fail. Moving the first clock after the read made `reads selected attribute with clock bounds` fail. Each changed copy reported `29/30 passed`; the unchanged implementation reported `30/30 passed`. These checks test the probe's safeguards, not Teams behavior.

No Ku-Ka app source or test target changes in this phase. App tests, UI screenshots, and model-based tests were not run. Later production work must use the requested worktree-local Xcode test path and fake capture, AX, and permission dependencies.

## Run only after the user confirms a suitable call

1. Ask in the parent conversation. Do not join or start a call to obtain evidence.
2. Use a Teams desktop meeting window with chats, captions, and shared content closed. Confirm the specific window with the user.
3. Obtain that Teams process ID and the exact focused meeting-window title. Do not list or dump unrelated Teams windows.
4. Supply those values as `teams_pid` and `meeting_title`. First read structure only:

```sh
"$probe_tmp/teams-ax-probe" --pid "$teams_pid" --window-title "$meeting_title" --confirm --mode structure --path ''
```

5. Inspect one structural level at a time. Set `participant_path` only after establishing which node belongs to a participant. Never reuse a guessed or old path after the layout changes.
6. Read only the participant attributes needed for the experiment. For example:

```sh
"$probe_tmp/teams-ax-probe" --pid "$teams_pid" --window-title "$meeting_title" --confirm --mode read --path "$participant_path" --attribute AXDescription
"$probe_tmp/teams-ax-probe" --pid "$teams_pid" --window-title "$meeting_title" --confirm --mode read --path "$participant_path" --attribute AXDOMClassList
```

7. Take separate snapshots during silence, participant A speaking, participant B speaking, and overlap. The user identifies who is speaking. A class name, mute state, participant roster, or last-speaker highlight alone is insufficient.
8. Stop on loss of permission, window mismatch, unavailable elements, or uncertain scope. Do not activate a screen-reader flag to obtain a richer tree under this read-only authorization.
9. Remove this run's scratch directory after its processes end:

```sh
rm -r "$probe_tmp"
```

These are conditional commands. None of the live commands ran on 2026-10-29.

## Evidence needed to proceed

| Check | Needed evidence | Current result |
| --- | --- | --- |
| Participant names | Attribute and element relationship that identify actual remote participant controls | Not measured |
| Speaking state | The same participant changes state with speech and silence; a second participant produces a distinct result | Not measured |
| Name association | The indicator belongs to that participant, without guessing from an unrelated name or label | Not measured |
| Overlap | What two simultaneous speakers expose; preserve uncertainty | Not measured |
| Missing UI | Behavior when tiles disappear, sharing starts, the window is hidden, or AX fails | Not measured |
| Timing | Observation intervals and visible state transitions, including stale last-speaker state | Not measured |

Record the Teams and macOS versions with future observations. Record sanitized roles, attribute names, changed values, and timestamps. Clearly separate an observation from an inference. Public source examples are research leads, not observations on this Mac. See [open-source research](2026-10-29-teams-open-source.md).

## Existing integration boundaries

The code review found these constraints. They do not choose a production design.

- `MeetingRecorder` owns capture, permission checks, pause, resume, stop, interruption, quit, and late-result rejection. Start can fail or end before capture startup returns.
- `RecordingClock.filePosition(at:)` returns nil during pauses. Final transcript positions include three seconds for each earlier resume. The displayed timer excludes those gaps. A future observer must use the same host clock and mapping.
- `MeetingNotesController` currently queues only a `MeetingFolder`. Any later memory-only evidence handoff must account for queue delay, cancellation, quit, and crash recovery. A lost observation must keep the fallback `Them`.
- `Speaker` currently has `me`, `them`, and `room`. `Transcript.merge` assigns system segments to `Them` before joining lines. Joined lines no longer retain segment end times. Keep microphone room labels and echo filtering intact.
- `MeetingProcessor` writes the heard transcript before known-word correction. Update Notes starts from that heard text. Preserve that rule, the meeting-context input, CLI isolation, and audio disposal after a transcript exists.
- `SummaryPrompt` requires evidence for action ownership. Identifying the speaker does not establish that the speaker accepted an action.

No shared production interfaces change. Task #43 owns persistent settings controls. Task #28 owns calendars and reminder association. Remote voice diarization belongs to #27. A future speaker-domain change needs coordination before modifying `Speaker`, transcript handling, or the recorder-to-queue handoff.
