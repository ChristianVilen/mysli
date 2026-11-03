# Measurements moved out of AGENTS.md

These measurements were in `AGENTS.md` until 2026-11-03. They explain why the code works as it does, but no single constant depends on them. Measurements that explain a constant are in a comment next to that constant. The speaker-label measurements are in `2026-10-28-speaker-labels.md`, and the live-panel measurements are in `2026-10-27-floating-meeting-panel.md`.

## Audio capture

Measured on macOS 27 with one `SCStream`:

- Both tracks arrive without a `.screen` output.
- Both tracks use the host clock. The first buffers of the two tracks were 70 ms apart.
- A CAF file that `AVAudioFile` was writing is readable after `kill -9`.

Not measured yet: whether Whisper writes a silence phrase into the 3 s resume gap.

## Live transcript

`RealLiveTranscriptTests` ran Apple's live engine at real-time pace on generated meetings.

| Meeting | Preset | First text | Final text after its audio (median) |
| --- | --- | --- | --- |
| 253.7 s, two tracks | `.progressiveTranscription` | 1.09 s | Me 0.94 s, Them 0.85 s |
| 296.6 s, three voices on the microphone and one on the system track | `.timeIndexedProgressiveTranscription` | 1.09 s | Me 0.93 s, Them 0.91 s |

In the second meeting, every word time was inside the range of its result. Of the 43 turns that follow another person on the microphone track, 42 started a new row.

The echo rule applies to each final phrase. A phrase is shorter than a result, so the rule more often hides a real microphone sentence of 3 or more words when a system phrase within 1 s shares 60% of its words. In the room meeting, it hid 2 sentences:

- "Nothing from me." before "Nothing from me either." This is the one turn without a row.
- "I will be your backup." after "... if someone from your side is my backup."

## Whisper

`RealMeetingAudioTests` ran on an M5 Pro, Release build, with a 66.5-minute meeting:

- One load serves both tracks. The Them track took 86 s and the Me track 61 s, the same in two runs.
- The download took 49 s.
- The first load took 57 s, because it also compiles the model for this Mac. Later loads took 0.6 s. macOS removes the compiled model after an OS update or a long time without use.

About a quarter of the Them segments (124 of 517) start in lowercase. Most are fragments without punctuation, and the silence filter keeps them.

## Apple speech recognition

Measured on macOS 27:

- One `SpeechTranscriber` result is a sentence or longer.
- The supported locales cover English, German, Spanish, French, Italian, Portuguese, Japanese, Korean, Chinese, and several Indian languages. Finnish is not supported.
- Only the English models come installed.

## agy

- `-p` needs the prompt as its value. Text mode does not read stdin.
- `--mode plan` has no effect together with `--disable-slash-commands`.
- No flag turns tools off. Only a hook of the user can block them.
- `agy` saves every run under `~/.gemini/antigravity-cli/conversations/`.
