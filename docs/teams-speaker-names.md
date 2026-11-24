# Teams speaker names (experimental)

**Teams speaker names** on the Meetings page of Settings starts off. When it is on, Mysli reads speaker indicators and participant labels from the Teams desktop app through Accessibility while you record. A final remote line can show `Aino (Teams)` in the live transcript and in the transcript after Stop.

## What is verified

Treat the names as best effort. The rules come from public source code and tests with fake Accessibility trees. In one real call, a standalone scanner identified a remote speaker beside a shared screen. A separate script enabled access to the Teams call. In a real call of 57 minutes on 2026-11-23, 74% of the scans read a name, but only 1 of 62 remote lines got one. The rule at that time rejected a segment for one scan without a name. The rule is now a clear majority, see [When a line gets a name](#when-a-line-gets-a-name). The majority rule, the gallery view, and the local speaker's tile still need a real-call check.

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

Mysli checks each segment of speech from the Mac audio track before it joins segments into transcript lines. The segment gets one name or stays "Them". Mysli never names a part of a segment.

Mysli scans Teams about every 0.4 seconds. Each scan counts for its own time and for half of the interval to the scan before it and to the scan after it. Each part of a segment is then one of these:

- **A name.** The scan found one speaking border and read its name.
- **Silence.** The scan found no speaking border. A short stop between sentences gives this result, so silence does not count against a name.
- **Unknown.** The scan found more than one speaking border, failed, or took too long. Time without a scan is also unknown, for example when two scans are more than 0.75 seconds apart or when the Teams window changes.

A segment gets a name when all of these are true:

- One name has at least 70% of the time that is not silence.
- No other name has more than 15% of that time.
- The name has at least 25% of the whole segment.

So a segment with two speakers of similar parts, or with too much unknown time, stays "Them". Overlapping speech segments also stay "Them".

- Mysli does not guess from a roster, a muted microphone, a calendar, or a voice profile.
- A final live row can gain a name when later scans cover it. Draft remote rows show "Them". The transcript after Stop can use different speech segments, so the labels can differ.
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

`transcript.md` also gets a note when fewer than 25% of the Mac audio lines got a name. That note gives the count of named lines and the most frequent scan problem.

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
