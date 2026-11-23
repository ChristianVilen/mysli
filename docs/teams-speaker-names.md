# Teams speaker names (experimental)

**Teams speaker names** on the Meetings page of Settings starts off. When it is on, Mysli reads speaker indicators and participant labels from the Teams desktop app through Accessibility while you record. After Stop, a remote line in the transcript can say `Aino (Teams)` instead of "Them".

## What is verified

Treat the names as best effort. The rules come from public source code and tests with fake Accessibility trees. In one real call, a standalone scanner identified a remote speaker beside a shared screen. A separate script enabled access to the Teams call. The gallery view, the local speaker's tile, and the names in a finished transcript still need a live check.

Teams can change its interface, hide its speaking indicator, or keep the last speaker highlighted. Names can be missing or wrong.

See the [live measurement](superpowers/research/2026-11-09-teams-ax-tree.md#our-measurement-in-a-real-call-on-2026-11-16) and the [probe instructions](superpowers/research/2026-10-29-teams-ax-feasibility.md).

## Turn the feature on or off

Turn **Teams speaker names** on or off in Settings. Mysli reads the preference at the start of each recording. To change it from Terminal, quit Mysli and run this command with `true` or `false`.

```bash
defaults write io.github.christianvilen.mysli teamsSpeakerNamesEnabled -bool true
```

Reopen Mysli after you run the command.

## What Mysli reads from Teams

- Mysli looks for English meeting controls and speaking indicators in Teams. The participant strip beside a shared screen is the layout checked in a real call.
- Mysli tries to set the `AXEnhancedUserInterface` flag to show the call to Accessibility. It tries to clear its changes when observation ends at pause or Stop. A flag that already reads `true` stays on.
- Moving or resizing the Teams window can be slow while the flag is on. The call can stay visible to Accessibility after the flag is cleared.
- To get names, grant Mysli Accessibility access in macOS. The option adds no permission prompt and Mysli does not click controls or open chats in Teams.
- If Accessibility is not available or the layout is not supported, the recording continues and the remote lines stay "Them".

## When a line gets a name

Mysli checks each segment of speech from the Mac audio track before it joins segments into transcript lines. A segment can get a name when intervals between matching scans in the same Teams window and recording run cover at least 90% of the segment. Conflicts, overlapping speech segments, or too little coverage keep the label "Them".

- Mysli does not guess from a roster, a muted microphone, a calendar, or a voice profile.
- The live draft and the "Room" labels of the microphone do not change.
- The Mac audio track can include other apps. A Teams indicator can therefore lead to a name on speech from outside Teams.
- The summary prompt asks for an action owner only when the transcript or typed notes say who will do the task.
- Pause stops observation. Resume starts a new run and adds the same 3-second gap to the observation timeline as to the audio.
- Mysli keeps at most 36,000 observations for each recording. At that limit it stops collecting and keeps the earlier observations.

## What Mysli keeps

Observations stay in memory until the meeting is processed. A quit, a crash, or a retry before the transcript exists loses them, and those lines stay "Them". After the names are in the transcript, **Update Notes** keeps them.

Mysli saves names in `transcript.md` and `.transcript-as-heard.md`. A flagged quote can also carry its speaker name in `review.json`. The summary tool receives the names with the rest of the transcript and can repeat them in the summary. Mysli saves no participant list, Accessibility tree, or voice profile.

## Find out why no name appeared

If Mysli made at least one scan and produced at least one Mac audio line, `transcript.md` can explain why every Mac audio line stayed "Them". If a scan found a name, the note says that no line had enough matching evidence. Otherwise, it gives the most frequent scan problem, with an unhighlighted tile used only when there is no other reason. For example:

> Teams speaker names were on, but no remote line got a name. In 380 of 412 scans, no Teams window showed meeting controls with Hang up or Leave.

Mysli also writes the scan results to the macOS log. The log lines hold only reason codes, counts, and scan times, never a name or other text from Teams.

To watch the lines while you record, run:

```bash
/usr/bin/log stream --predicate 'subsystem == "io.github.christianvilen.mysli" AND category == "teams"'
```

To see the lines of the last two hours, run:

```bash
/usr/bin/log show --last 2h --predicate 'subsystem == "io.github.christianvilen.mysli" AND category == "teams"'
```

Use the full path `/usr/bin/log`, because zsh has its own `log` command.
