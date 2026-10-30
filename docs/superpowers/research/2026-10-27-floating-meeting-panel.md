# Floating meeting recorder panel

Status update, 2026-10-29: the floating panel, Pause/Resume, and live transcript shipped in [PR #45](https://github.com/ChristianVilen/ku-ka/pull/45). The live engine uses `timeIndexedProgressiveTranscription`. This note preserves the research and earlier proposals. Current behavior is in [README.md](../../../README.md#meeting-notes) and [AGENTS.md](../../../AGENTS.md#meeting-notes-implementation).

Research and design, 2026-10-27. No production code is part of this note. The user reviewed the mockup and answered the design questions on 2026-10-27.

## How to read this note

Each statement has one of four labels.

- **Fact.** A cited source says it: a repository line, an SDK header, an Apple page, or a paper.
- **Measured.** It ran on this Mac in this session. The run count is given. Generated speech from `say` is cleaner than a real meeting, so accuracy numbers are an upper limit.
- **Proposal.** It is the author's judgment. The user can change it.
- **Open.** Nobody knows yet. The note says what would settle it.

All measurements ran on an Apple M5 Pro with 18 cores, macOS 27.0.1 (26A434), and Xcode with the macOS 27 SDK.

## Summary

The user wants Granola-like floating controls: Pause, Resume, Stop, and a live view of what is said. The user chose compact controls that open into a live transcript. The final Whisper pass after Stop stays the source of truth.

1. **Layout. The user chose layout A.** A small pill under the menu bar, near the Ku-Ka icon, with a transcript drawer that opens on request. **Proposal.** Every meeting starts with the drawer closed, because macOS has no supported way to keep a window out of a shared screen.
2. **Pause. Decided.** Pause is a real recorder state. Both tracks drop the same paused span, chosen by buffer presentation time. The capture stream keeps running, so the system microphone dot stays on during a pause. The files get 3 s of silence at each resume, so the final transcript never joins speech across a pause. The timer shows recorded time and stops while paused.
3. **Live transcript engine. Decided.** Use Apple's `SpeechTranscriber` with the `progressiveTranscription` preset. No live text for a language it does not support, such as Finnish. Whisper stays the final pass. On generated speech, both engines keep up. With no other work, confirmed text came 0.68 s (Apple) and 0.74 s (Whisper) after a sentence ended, 5 runs each. While an earlier meeting's final Whisper pass ran, Apple's text came after 1.75 s and did not slow that pass. Whisper's came after 2.74 s, at most 7.4 s, and the final pass was 47% slower. Apple also runs in a system process and needs less new code. The user judged its quality good enough for the live view. See [Measured: can a live engine keep up](#measured-can-a-live-engine-keep-up). **Changed on 2026-10-28:** the live engine uses `timeIndexedProgressiveTranscription` instead, so that each word has its audio time and each sentence can be a row of its own. See `AGENTS.md`, "Meeting notes implementation".
4. **Nothing provisional reaches the disk.** The live text stays in memory and goes away at Stop. `transcript.md` still means that transcription finished, so the audio can go to the Trash.

The user's answers are in [Answers from the user](#answers-from-the-user). The second status item goes away, and the live text is not selectable.

## Decisions the user already made

- Compact controls with an expandable live transcript.
- Layout A from the mockup, the pill with a drawer. The user chose it after the mockup review on 2026-10-27.
- The six design answers of 2026-10-27, listed in [Answers from the user](#answers-from-the-user).
- A visual mockup before the written design.
- Test-driven development for the build, with subagents doing the development work.
- The final Whisper transcript after Stop stays as it is, with the same quality and the same crash recovery.
- No live audio recording, no personal meetings, and no model download during research.

## Code facts that shape the design

These are facts from the repository at `e5164d3`.

1. The recorder has three states, `idle`, `starting`, and `recording` (`KuKa/MeetingNotesController.swift:5-9`). `isRecording` is true only for `recording` (`:40-43`).
2. Nine places depend on `isRecording`. In `AppDelegate`, they are the quit guard (`KuKa/AppDelegate.swift:37`), the menu bar icon (`:274-279`), the icon's accessibility label (`:280`), its tooltip (`:281`), and the second status item with the stop button (`:282`, `:286-298`). In `MeetingNotesController`, they are the title of the record item (`KuKa/MeetingNotesController.swift:290`), the audio meter row (`:291`), and the meter timer (`:302`, `:305`). The menu's status line switches on the recorder state itself (`:286-288`). A paused state must reach all of them.
3. One `SCStream` delivers both tracks to one serial queue. The first buffer of either track sets `timelineStart`, and both writers measure from it (`KuKa/MeetingAudioCapture.swift:94-97`, `:116-131`).
4. `AudioTimeline.silenceFrames` pads a gap between the file position and the next buffer's start with silence (`KuKa/MeetingAudioCapture.swift:201-203`, `:252-258`). If Pause only dropped buffers, Resume would fill the whole pause with silence.
5. `AudioTrackWriter.init` opens the file with `AVAudioFile(forWriting:)` (`KuKa/MeetingAudioCapture.swift:177-180`). A second `capture.start(into:)` on the same folder would create the file again and lose what was recorded.
6. The converter keeps its state between buffers on purpose (`.noDataNow`, `KuKa/MeetingAudioCapture.swift:211-219`).
7. The controller holds the folder lock for the whole recording (`KuKa/MeetingNotesController.swift:151`). A paused meeting must keep it.
8. The stage comes from the files. `transcript.md` means transcription finished (`KuKa/MeetingFolder.swift:57-71`), and the summarize step then moves `audio/` to the Trash (`KuKa/MeetingProcessor.swift:145`).
9. Final timestamps come from positions in the audio files. `Transcript.merge` joins one speaker's segments when the gap is under 2 s (`KuKa/Transcript.swift:21`, `:33`).
10. A new recording can start while the queue still processes an earlier meeting. `toggleRecording` checks only the recorder state (`KuKa/MeetingNotesController.swift:129-134`). A live engine can therefore run at the same time as a final Whisper pass.

## Pause and resume

### What the code and the converter do

**Measured, deterministic, run once.** A throwaway program fed synthetic 48 kHz, 44.1 kHz, and 24 kHz buffers through `AVAudioConverter` the way `AudioTrackWriter` does. The converter held back 6 to 11 output frames at 16 kHz, which is 0.35 to 0.69 ms. With a drain (`.endOfStream`) and `reset()` at the pause, no pre-pause sample came out after the resume. Without a drain, 5 frames (0.3 ms) of pre-pause audio came out at the start of the first buffer after the resume. That is pre-pause audio, slightly late. It is never audio from the paused span.

So the converter cannot leak paused audio. Paused audio can only reach the file if Ku-Ka feeds a paused buffer to the writer. The boundary rule below is what keeps that from happening.

**Inference.** ScreenCaptureKit delivers a buffer some time after its presentation time. When the user clicks Pause, buffers from before the click can still be in the queue. A rule based on "when the queue sees the request" would cut at the wrong place, and it could cut the two tracks at different places.

**Fact.** macOS shows an orange dot while an app uses the microphone and a purple dot while an app records system audio ([menu bar guide](https://support.apple.com/guide/mac-help/whats-in-the-menu-bar-mchlp1446/mac)). **Inference, not tested.** If the stream keeps running during a pause, the dot stays on while Ku-Ka says Paused.

### Proposal

1. **A shared recording clock.** `ScreenCaptureRecording` owns one list of paused spans in host time, and both writers use it. The recorded position of a buffer is its presentation time minus `timelineStart`, minus all paused time before it, plus one boundary gap per earlier pause. The clock is a pure value, so tests can drive it with literal times.
2. **The boundary is the click.** The controller reads the host clock when the user clicks Pause or Resume and sends that time to the sample queue. A buffer that ends before the pause time is written. A buffer that starts after it is dropped until the resume time. A buffer that crosses the pause time is cut at the frame for that time. The same rule applies to both tracks.
3. **Drain the converter at the boundary.** At the pause point the writer drains the converter and resets it. The measured hold-back is under 1 ms, so this is for an exact boundary, not for privacy.
4. **A short silence marks each pause in the audio.** The clock puts each resume 3 s after the pause point, and `AudioTimeline` writes that gap as silence on both tracks. The final Whisper pass then sees a pause, and `Transcript.merge` cannot join speech across it, because the gap is more than its 2 s limit. The files alone carry the boundary, so crash recovery needs nothing new. The cost is 3 s of extra duration per pause in `transcript.md`. The 3 s value is a guess to check in a test with real Whisper output.
5. **Keep the stream running during a pause. Decided by the user, as the simpler option.** The `SCStream`, the writers, the files, and the folder lock all stay. The sample queue drops the paused buffers by the clock of proposal 1. Resume cannot fail, because nothing restarts. The system microphone dot stays on while the panel says Paused. The other option was to stop the stream at Pause and start a new one at Resume, so the dot goes off. It needed a live-capture test and a failure path at Resume.
6. **Paused is a recorder state.** The controller has `idle`, `starting`, and an active session with a `recording` or `paused` phase. Every place in code fact 2 reads the phase. The quit alert also covers a paused meeting. The icon shows a different mark for paused. The label and tooltip say "recording paused". The Ku-Ka menu gets Pause Recording and Resume Recording. While paused, the record item still says Stop Recording Meeting, and the status line says "Paused" with the recorded time. **Inference.** The meters go quiet by themselves during a pause. They read the level that `AudioTrackWriter.append` returns, the writer gets no paused audio, and a reading expires after 0.5 s.
7. **The timer shows recorded time.** It stops while paused. The wall-clock start stays in the folder name. The 3 s silence of proposal 4 is in the files but not on the timer. So a time in `transcript.md` is 3 s later than the pill showed for each earlier pause. After five pauses, the difference is 15 s. The user accepted this.

**Not chosen.** Ku-Ka could also write `audio/pauses.json` with the exact boundaries, atomically at each pause and resume. `transcript.md` could then show "Paused at 12:41" lines, and the merge could split at the exact point. It is one more file to keep correct after a crash. The user accepted the 3 s silence of proposal 4 instead.

## Live transcript engine

### WhisperKit 1.1.1

These are facts from the pinned checkout, tag `v1.1.1`, commit `1bbc57cb` (https://github.com/argmaxinc/argmax-oss-swift/tree/v1.1.1). Paths that start with `Core/` are under `Sources/WhisperKit/`. Other paths start at the repository root.

1. Every window is padded to 30 s before the mel and encoder models run (`Core/TranscribeTask.swift:120-127`). The installed encoder input is fixed at 3000 mel frames. A short live window therefore costs a full encoder pass.
2. `AudioStreamTranscriber` records the microphone itself through `AVAudioEngine` and asks for microphone permission (`Core/Audio/AudioStreamTranscriber.swift:82-100`, `Core/Audio/AudioProcessor.swift:1033-1050`). It cannot record "Them". Its sample buffer grows for the whole session and is copied on every pass, because no code calls `purgeAudioSamples` (`Core/Audio/AudioProcessor.swift:940-949`, `:1057-1061`).
3. `WhisperKit` is an `open class` with no `Sendable` conformance (`Core/WhisperKit.swift:11`). Nothing promises that two calls on one instance are safe. The library itself makes such calls in its `concurrentWorkerCount` path (`Core/WhisperKit.swift:828-897`), and `progress` is a plain `var` that every call changes (`:50`, `:1147-1148`).
4. `TranscribeTask` is public and takes already-loaded model objects (`Core/TranscribeTask.swift:9`, `:21-39`). A preview could run its own task per track over Ku-Ka's loaded models, without a second 1.5 GB model load.
5. The upstream streaming examples, `--stream-simulated` in the CLI and "Eager" mode in WhisperAX, confirm text with LocalAgreement-2. Two passes must agree on a word prefix before it is confirmed (`Sources/ArgmaxCLI/TranscribeCLI.swift:388-421`). They need `wordTimestamps`, which adds an alignment pass per window. WhisperAX's eager mode sets `firstTokenLogProbThreshold` to -1.5 (`Examples/WhisperAX/WhisperAX/Views/ContentView.swift:2037-2051`). Ku-Ka measured that this threshold drops sentences, so Ku-Ka does not use it.
6. Transcription checks `Task.checkCancellation()` before every decoder token (`Core/TextDecoder.swift:412`). Returning `false` from the progress callback ends only the current decode, and a temperature fallback can then decode the window again (`Core/TranscribeTask.swift:394-405`).
7. The WhisperKit paper reports 0.45 s per-word latency for hypothesis text and about 1.7 s for confirmed text on an M3 Max ([arXiv 2507.10860](https://arxiv.org/abs/2507.10860), p. 6). That system used a modified encoder, compressed weights, and a stateful decoder. None of these parts is in 1.1.1, and the installed decoder takes its cache as inputs. The same paper gives 612 ms per pass for the unmodified turbo encoder on M3 Max (Table 1).
8. Whisper-Streaming measured 3.3 s mean latency for English with Whisper large-v2 on an NVIDIA A40 GPU and 1 s chunks ([arXiv 2307.14743](https://arxiv.org/abs/2307.14743), p. 5).

**Inference, made before the probe.** Two tracks every second would need about 1.2 s of encoder time per second on an M3 Max. A Whisper preview would need a slower cadence, alternation between tracks, and a voice gate that skips a quiet track. The probe used all three. It measured 0.279 s per encoder pass on the M5 Pro, so the M3 Max figure does not apply here.

### Apple SpeechAnalyzer and SpeechTranscriber

Facts come from the macOS 27 SDK interface `Speech.framework/.../arm64e-apple-macos.swiftinterface` (cited as `SI:line`), Apple's documentation, and WWDC25 session 277 (https://developer.apple.com/videos/play/wwdc2025/277/).

1. `progressiveTranscription` sets `volatileResults` and `fastResults`. Apple describes it as "immediate transcription of live audio" (SI:353, https://developer.apple.com/documentation/speech/speechtranscriber/preset). `timeIndexedProgressiveTranscription` adds `audioTimeRange`.
2. `fastResults` "Biases the transcriber towards responsiveness, yielding faster but also less accurate results" (https://developer.apple.com/documentation/speech/speechtranscriber/reportingoption/fastresults).
3. The analyzer does not convert audio (https://developer.apple.com/documentation/speech/speechanalyzer/bestavailableaudioformat(compatiblewith:)). **Measured.** For en-US, `bestAvailableAudioFormat` returns 16 kHz mono Int16 interleaved. That is `AudioTrackWriter.fileFormat` (`KuKa/MeetingAudioCapture.swift:169-170`), so the converted buffers can go in as they are.
4. A volatile result "may or may not" be replaced, and a module "is not required to provide new, final results" for a range whose volatile text did not change (https://developer.apple.com/documentation/speech/speechmoduleresult/resultsfinalizationtime). A client must treat an old volatile text as final once `resultsFinalizationTime` passes its range, or a sentence can disappear.
5. Apple documents a per-device limit on simultaneous analyses without a number, with the error `insufficientResources` (https://developer.apple.com/documentation/speech/speechanalyzer). macOS 27 adds `ignoresResourceLimits` (SI:454-456).
6. The model runs "outside of your application's memory space" (WWDC25 session 277). SpeechAnalyzer modules do not send voice audio to Apple (https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition).
7. **Measured.** `SpeechTranscriber` supports 45 locales on this Mac, and Finnish is not one of them. `DictationTranscriber` supports fi-FI, but the fi-FI asset is not installed.
8. **Measured, one run per configuration, generated speech, two tracks at real-time speed.** With `progressiveTranscription`, first text came after 1.0 s, updates came about once a second, and final text came at most 0.94 s after its audio. Without `fastResults`, updates came about every 4 s. Two, four, and eight analyzers ran at the same time with no error and no change in latency.

The full Apple notes, with all 53 facts, were working material for this note. The agent's command-line probe (not Ku-Ka) did not reserve or download any asset.

### Measured: can a live engine keep up

**Measured.** A throwaway probe in the scratch folder played a generated two-track meeting into each engine at real-time speed. The probe is not Ku-Ka code.

Setup:

- The meeting is invented. It has 43 utterances and 635 words in two `say` voices, Samantha for Me and Daniel for Them, and lasts 253.6 s. It has short replies, gaps of 0.4 to 1.3 s, two overlaps of 0.4 s and 0.6 s, and one 22 s silence. Both tracks are 16 kHz mono Int16 CAF, the format that `AudioTrackWriter` writes. A manifest holds the speaker, times, and text of each utterance. It is the reference for accuracy.
- A feeder thread releases 100 ms of both tracks at wall-clock pace.
- Whisper uses the `large-v3-v20240930_turbo` model that `whisperkit-cli` had installed in `~/Library/Caches/whisperkit-models`. It is the same variant that `WhisperKitTranscriber` downloads. Ku-Ka's own model folder does not exist on this Mac, so the first real run here downloads and compiles the model. The probe uses Ku-Ka's decoding options and loads the model once with `cpuAndNeuralEngine`. One worker makes one call at a time. For each track, it transcribes the audio from the last confirmed point to the live edge, every 0.5 s while that track has speech. Text is confirmed when two calls agree on it (LocalAgreement-2). The confirmed point then moves to the nearest silent 100 ms within 0.5 s. Without that rule, an earlier series lost the first word of some sentences, because Whisper's segment end fell inside the next word (error rates 2 to 5% for Me and 7% for Them). The window is capped at 10 s or 30 s. Two options differ from the final pass because the windows are short: `chunkingStrategy: .none` and `concurrentWorkerCount: 1`.
- Apple uses `SpeechTranscriber` with `timeIndexedProgressiveTranscription` in en-US, one `SpeechAnalyzer` per track, both at once. It gets the 16 kHz buffers with no conversion.
- The concurrent case adds a second WhisperKit instance. It runs Ku-Ka's final pass (VAD chunks, 4 workers) over the Them track again and again for the whole run, as the final pass of an earlier meeting would.
- Release build, no network, no download. Other work on the Mac gave load averages of 1.8 to 27.5 at the start of the runs. The sides ran interleaved, but the load still differed per run, up to 25.3 and 27.5 for two Apple runs. The results barely moved across runs. Apple's median was 0.67 to 0.69 s, and every Whisper call had a median of 0.37 s. Each round of the main series ran Whisper 10 s, Apple, and Whisper 30 s. Each round of the concurrent case ran Whisper 10 s and Apple.
- Latency is the wall time from the end of an utterance's audio to the first result that contains its last two words. "Provisional" is the first guess. "Confirmed" is Whisper's agreed text or Apple's final result. Each engine got the last two words of one or two of the 43 utterances wrong ("Bigger how?" became "Bigger huh?" in both). Those count in the error rate, not in the latency.

Results with no other work, 5 runs per side. Each value is the median of the runs, with the range across runs.

| | Whisper, 10 s cap | Whisper, 30 s cap | Apple |
|---|---|---|---|
| Provisional text, median | 0.25 s [0.25 to 0.28] | 0.26 s [0.23 to 0.28] | 0.24 s [0.24 to 0.28] |
| Confirmed text, median | 0.74 s [0.73 to 0.78] | 0.74 s [0.72 to 0.78] | 0.68 s [0.67 to 0.69] |
| Confirmed text, p90 | 1.06 s [0.97 to 1.09] | 1.06 s [1.06 to 1.08] | 1.03 s [1.02 to 1.04] |
| Confirmed text, max | 1.59 s [1.57 to 1.60] | 1.59 s [1.56 to 1.60] | 1.32 s [1.32 to 1.34] |
| Word error rate, Me and Them | 1.4% and 1.9% in every run | 1.4% and 1.9% in every run | 1.8% and 2.9 to 3.4% |
| Time per call, median | 0.37 s in every run | 0.37 s in every run | Not applicable |
| Worker busy | 46 to 47% | 46 to 47% | Not applicable |
| Lag behind the live audio, max | 1.8 to 1.9 s | 1.8 s | Not applicable |
| Errors, empty results, forced confirmations | 0, 0, 0 | 0, 0, 0 | 0, 0, 0 |
| CPU, share of one core | 5.6 to 6.1% | 5.6 to 6.3% | 0.6 to 0.8% in the probe. In `localspeechrecognition`, 1.4 to 2.2% median and 8 to 10% max (4 runs) |
| Memory | 246 to 250 MB | 247 to 250 MB | 40 MB in the probe, 118 to 126 MB in `localspeechrecognition` |

The window never grew past 6.5 s (median 2.3 s), because two calls agree within each sentence. So the 10 s and 30 s caps gave the same result.

Results while an earlier meeting's final pass runs, 3 runs per side:

| | Whisper, 10 s cap | Apple |
|---|---|---|
| Provisional text, median | 1.26 s [1.21 to 1.40] | 1.35 s [1.23 to 1.54] |
| Confirmed text, median | 2.74 s [2.68 to 2.87] | 1.75 s [1.70 to 1.78] |
| Confirmed text, p90 | 4.21 s [4.12 to 4.39] | 2.89 s [2.86 to 2.93] |
| Confirmed text, max | 6.97 s [5.77 to 7.43] | 3.14 s [3.12 to 3.24] |
| Word error rate, Me and Them | 0.5 to 2.3% and 1.2 to 5.1% | 1.8% and 2.9% in every run |
| Time per call, median | 0.84 s [0.83 to 0.84] | Not applicable |
| Worker busy | 87 to 88% | Not applicable |
| Lag behind the live audio, max | 4.6 s [4.2 to 4.8] | Not applicable |
| Forced confirmations | 4 [1 to 9] | 0 |
| Errors, empty results | 0, 0 | 0, 0 |
| One final pass of the Them track | 12.84 s [12.74 to 12.84] | 8.74 s [8.72 to 8.76] |

One final pass of the Them track takes 8.74 s with no preview running (one run). The Apple preview did not slow it. The Whisper preview made it 47% slower. Whisper's lag did not grow during a run. Its highest value in each minute stayed between 3.1 s and 4.6 s. A forced confirmation happens when the unconfirmed audio grows past the 10 s cap. In 13 of the 14 forced confirmations, no text was ready, so the preview moved past that audio and never showed its words. In the run with 9 of them, the Them track lost 17 words.

The verdict:

- **Measured.** With no other work, both engines keep up with one speaker at a time. Their latency differs by less than 0.1 s at the median, so speed does not decide between them.
- **Measured.** While an earlier meeting's final pass runs, both still keep up with no errors. Apple's final text comes 1.75 s after a sentence ends, at most 3.2 s, its accuracy does not change, and the final pass is as fast as alone. Whisper's confirmed text comes 2.7 s after a sentence ends, at most 7.4 s, it can skip audio and never show its words, and the final pass gets 47% slower.
- **Measured, one run.** Ku-Ka's final decode path got every spoken word right on both tracks. Its only errors were 13 (Me) and 15 (Them) added words, mostly "Thank you." written over silence. Ku-Ka's silence filter removes a "thank you" segment of 8 s or more (`KuKa/WhisperKitTranscriber.swift:89-92`), and the probe did not apply that filter. Both previews got some spoken words wrong. Clean generated speech does not show how Apple's live text compares with Whisper on real meetings. The user judged Apple's quality good enough for the live view.

The limiting resource:

- **Measured.** For Whisper, the encoder. WhisperKit pads every window to 30 s, so every call spends 0.279 s in the encoder, whatever the window length (WhisperKit's own `timings.encoding`, 301 calls). The decoder adds about 7 ms per token. A 1 s window takes 0.35 s and a 6 s window 0.45 s.
- **Measured, median of 5 calls.** The encoder takes 0.27 s with `cpuAndNeuralEngine` and 0.96 to 0.98 s with `cpuOnly`. The probe used about 6% of one CPU core while its worker was busy 46% of the time. So the preview's encoder runs on the Neural Engine, not on the CPU.
- **Measured, median of 5 calls.** With `cpuAndGPU`, the encoder takes 0.25 to 0.26 s, and the model loads in 3.1 s instead of 0.6 s. **Open.** A Whisper preview on the GPU might not compete with a final pass on the Neural Engine. The concurrent case was not run on the GPU, and the GPU was idle during these calls. In a real meeting, the video call also uses the GPU.
- **Measured.** Apple's work runs in the `localspeechrecognition` system process (118 to 126 MB while a run is active, 3 MB when idle), so the probe cannot see its limit.

The arithmetic:

- About 312 calls of 0.37 s take 115 s of a 254 s run. That is the measured 46% busy time, so the numbers agree.
- **Inference.** One person who talks needs 0.37 s of worker time per 0.5 s step, which is 74%. Two people who talk at the same time need 148%. The worker then serves each track about every 0.75 s instead of every 0.5 s. The delay stays bounded, because every window takes the newest audio. The two short overlaps in the script did not test this.
- The final pass transcribes about 46 s of audio per second of work (66.5 minutes in 86 s, from `AGENTS.md`). The preview's windows add up to 6.9 s of audio per second of work, so it costs more per second of audio, for two reasons. Every call pays the full 30 s encoder for a window of about 2 s. And the windows overlap. They add up to about 812 s for the 201 s of speech in the script, so each second of speech went through about four calls.

Caveats:

- Generated speech is clean. Real meetings, laptop echo, and compressed call audio will give more errors, so these error rates are a lower bound. The silence of generated speech is exact zero, so the probe's voice gate (RMS above 0.01) is always right here. A real microphone needs a tuned gate.
- `ps` reports CPU as an average over the process lifetime on macOS. The probe's CPU numbers come from user plus system time divided by wall time (`/usr/bin/time`). The numbers for `localspeechrecognition` come from `top` samples over 1 s.
- The script has only two short overlaps, so the probe did not test two people who talk at the same time for long.
- The probe measured no power use and no meeting longer than 254 s.

### Engine alternatives

| | Apple `progressiveTranscription` | Whisper rolling window | No live text |
|---|---|---|---|
| Confirmed text after a sentence ends, median. No other work, then during an earlier meeting's final pass | 0.68 s, then 1.75 s (max 3.2 s) | 0.74 s, then 2.74 s (max 7.4 s) | None |
| Effect on a final pass that runs at the same time | None measured | 47% slower | None |
| Quality | Lower than Whisper on a real 66-minute meeting with the `.transcription` preset (commit `f23a0ac`). The live preset trades accuracy for speed | Same model as the final pass, on short windows | Not applicable |
| Finnish | No. `DictationTranscriber` would need a download | Yes | Not applicable |
| Cost to Ku-Ka | A system process does the work, about 2% of one core and 120 MB. About 40 MB in Ku-Ka | Neural Engine busy 46% of the whole run, and about 74% while one person talks. Shares Ku-Ka's 1.5 GB model | None |
| New code | Two analyzers, a result model | A scheduler, voice gate, agreement rule, stale-result rejection | None |
| Risk to recording | Low. Runs out of process | Must never block the sample queue or starve a final pass | None |

### Proposal

**Decided.** The user accepted this proposal, judged Apple's quality good enough, and needs no Finnish live text.

Use Apple for the live text, and keep Whisper for the final pass. Both engines keep up, so speed does not decide. While a final pass runs, Apple still keeps up with no backlog and the same accuracy, although its final text slows from 0.68 s to 1.75 s. It does not slow that pass, and it needs less new code. Do not build a Whisper preview. On the Neural Engine, it slows the final pass by 47%, lags up to 7.4 s, and can skip audio. If Finnish live text is ever wanted, measure a Whisper preview on the GPU first, with a video call running, because the call also uses the GPU.

- Use Apple `progressiveTranscription` for the live text when `SpeechTranscriber.installedLocales` contains the meeting locale. `SpeechTranscriberAdapter.needsDownload` already makes this check (`KuKa/MeetingTranscriber.swift:50`). Do not use `AssetInventory.status(forModules:)` for it. In the research run, it returned `supported`, not `installed`, for en-US, although the model was installed and analysis worked. Show "Live transcript is not available for this language" otherwise. Never start a download for the live text.
- Feed each analyzer the converted 16 kHz buffer that `AudioTrackWriter` just wrote, through a bounded hand-off from the sample queue. Inference never runs on the sample queue. Paused audio never reaches the analyzer, because the writer drops it first.
- Keep one result model per track, with its final segments and one volatile tail. Merge the two tracks by start time, as `Transcript.merge` does, and apply `Transcript.isEcho` to final segments so laptop-speaker echo does not show twice.
- At Stop, cancel the analyzers with `cancelAndFinishNow()` and discard the text. The final Whisper pass starts as it does today.

## Panel design

### Facts from Apple, macOS, and Granola

1. Liquid Glass "forms a distinct functional layer for controls and navigation elements". The HIG says "Don't use Liquid Glass in the content layer" (https://developer.apple.com/design/human-interface-guidelines/materials).
2. `NSWindow.SharingType.none` is "A legacy constant that macOS no longer uses", and Apple says not to use it to hide content from capture (https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none). An Apple DTS engineer wrote in July 2025 that "there are no public APIs for preventing screen capture" (https://developer.apple.com/forums/thread/792152).
3. Live Captions on Mac is a floating window that can be moved and resized from any edge. It has a pause button in the window, the same command in the menu bar, and Restore Default Position (https://support.apple.com/guide/mac-help/get-captions-of-spoken-and-computer-audio-mchldd11f4fd/mac).
4. Granola's help center describes a "live meeting indicator floating on the right-hand side of your screen" that people drag by a handle. Its live transcript and its Stop and Resume controls are in a panel inside the note, labelled "Me" and "Them" (https://docs.granola.ai/help-center/taking-notes/transcription). Granola's official pages say nothing about pause controls or a transcript in the indicator itself, or about how it shows in a shared screen.
5. `hidesOnDeactivate` defaults to true for `NSPanel` (https://developer.apple.com/documentation/appkit/nswindow/hidesondeactivate). Ku-Ka never activates, so the panel must set it to false, as `ClipboardPanel` already does.
6. With `becomesKeyOnlyIfNeeded`, a non-activating panel becomes key only when the clicked view needs it (https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded). Buttons do not (https://developer.apple.com/documentation/appkit/nsview/needspaneltobecomekey). A click on Pause therefore does not take typing away from the meeting app.
7. `.statusBar` level (25) is above the Dock (20) and the menu bar (24). `.floating` (3) is below both (SDK `CoreGraphics.framework/Headers/CGWindowLevel.h`).
8. AppKit constrains only titled windows to the screen (https://developer.apple.com/documentation/appkit/nswindow/constrainframerect(_:to:)). A borderless pill must keep itself on screen after a display change.
9. The HIG says "Avoid displaying alerts for common, undoable actions, even when they're destructive" (https://developer.apple.com/design/human-interface-guidelines/alerts) and "Convey information with more than color alone" (https://developer.apple.com/design/human-interface-guidelines/accessibility).
10. With Reduce Motion, the HIG lists "Replacing transitions in x-, y-, and z-axes with fades" (https://developer.apple.com/design/human-interface-guidelines/accessibility).
11. WCAG 2.2 success criterion 2.2.2 needs a way to pause, stop, or hide information that updates by itself. For real-time content, freezing the view and then jumping to the current state is the better form (https://www.w3.org/WAI/WCAG22/Understanding/pause-stop-hide.html).
12. Android's `TRANSCRIPT_MODE_NORMAL` scrolls to the newest item "only if the last item is already visible on screen" (https://developer.android.com/reference/android/widget/AbsListView). No Apple source describing this rule was found.
13. VoiceOver announcements take a priority: low 10, medium 50, high 90 (SDK `AppKit.framework/Headers/NSAccessibilityConstants.h`).

### Layout alternatives

The mockup has A, B, and C behind one switcher.

| | A. Pill with a drawer | B. Captions bar | C. Menu bar popover |
|---|---|---|---|
| State and time always visible | Yes | Yes | In the menu bar only |
| Meeting text on screen by default | No | Yes, the newest line | No |
| Risk in a shared screen | Low while closed | High | Low |
| Watch text while working in the call | Yes, when opened | Yes | No. A popover closes on an outside click |
| Native precedent | Granola's floating indicator | Live Captions | The HIG prefers a menu for menu bar extras |
| Window work | Two sizes, own screen clamping | A resizable window | Little |

**Decision.** The user chose A. It answers "am I recording, for how long, pause, stop" at the smallest size, and it keeps meeting text off a shared screen until the user opens it. B was the better choice only if the user wanted the newest line visible all the time. C fails the goal of watching the transcript during the call. A notch-docked pill was considered and left out. Many displays have no notch, and a transcript that drops from the top center covers the meeting video.

### Proposed details

Window:

- Subclass `FloatingPanel`: borderless, `.nonactivatingPanel`, `.floating` level, `hidesOnDeactivate = false`, `collectionBehavior` `[.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`, `becomesKeyOnlyIfNeeded = true`, and `canBecomeKey` true for keyboard use. The transcript text is not selectable.
- Glass only on the pill (`NSGlassEffectView`). The drawer is content, so it gets a near-solid background.
- Default position is the top-right corner of the visible frame, 16 pt in. The whole pill background drags it. Ku-Ka remembers the position and clamps it to a screen after a drag or a display change. The drawer opens upward when the pill is near the bottom edge. The menu has Restore Default Position.
- The drawer height is resizable from its far edge and remembered.

States:

- Starting. A spinner and "Starting". Pause and Stop are off. Cancel during start is new controller work and is not proposed for the first version.
- Recording. The red ring with a white center, as on the menu bar icon, and the recorded time. No pulsing.
- Paused. Two bars, the word "Paused", a stopped and dimmed time, and a Resume button with a text label. Shape, word, and label all change.
- Live text loading. The pill does not change. The drawer says "Preparing live transcript" and that recording is not affected.
- Live text unavailable. The pill does not change. The drawer explains why in one sentence and says the full transcript comes after Stop.
- Live text behind. A chip with the delay in seconds.
- Saving, then saved. The pill says "Saving", then "Recording saved" with one line about the notes and a Close button. It closes by itself after a few seconds.
- Interrupted. "Recording stopped" with the reason. It stays until the user closes it, so the end of a recording is never hidden.

Transcript drawer:

- Rows start with "Me" or "Them" in text and color, with the recorded time on a speaker change. Provisional words are in the secondary color and end with an ellipsis. A finished row turns solid.
- The header says "Live transcript" and "Draft until you stop".
- The drawer follows new text only while the last row is visible. When the user scrolls up, a "Return to live" button shows the count of new rows. End in the transcript does the same.
- VoiceOver gets announcements for state changes only, at medium priority, and high priority for an interruption. Transcript rows are not announced.

Keyboard and menu:

- The Ku-Ka menu gets Pause Recording or Resume Recording, Show Meeting Controls, and Restore Default Position, next to Stop Recording Meeting. Keyboard and VoiceOver users never need the panel.
- When the panel is key, Tab moves between controls and Space presses the focused one. Esc closes the drawer and gives focus back.
- No bare-key shortcut such as Space for Pause. With Full Keyboard Access, Space presses the focused control, which could be Stop. No new global shortcut in the first version.
- No confirmation for Stop. Stop keeps all audio, and the HIG advises against alerts for deliberate actions. Pause and Stop have different shapes and space between them.

Motion and appearance:

- Reduce Motion. The drawer fades instead of growing, nothing slides or spins, and Return to live jumps.
- Reduce Transparency. Solid backgrounds.
- The live text is never the only way to know the state. The menu bar icon keeps its recording mark when the panel is hidden.

## Architecture sketch

**Proposal.** This is a starting point for the architect step after the user approves the design. It is not a final shape.

- `RecordingClock`. A pure value: `timelineStart`, the list of paused spans, and the boundary gap. It maps a host time to a recorded time and says which frames of a buffer to keep. Tests use literal times.
- `ScreenCaptureRecording`. Gains `pause(at:)` and `resume(at:)`. It owns the clock and the writers and applies the clock on the sample queue. The stream keeps running during a pause.
- `AudioTrackWriter.append`. Takes the frames to keep from the clock and drains the converter at a boundary. Its existing CAF and padding rules stay.
- `MeetingNotesController`. `Recorder` becomes `idle`, `starting`, or `active(Session)` with a `recording` or `paused` phase. `isRecording` is replaced by the phase for every reader in code fact 2.
- `LiveTranscript`. A pure model per meeting. It holds the final segments and one volatile tail per track, the merge by start time, and the echo rule for final segments. Tests feed it literal results.
- `LiveTranscriber`. A protocol with the Apple implementation. It receives converted buffers through a bounded hand-off and publishes `LiveTranscript` changes to the main actor a few times a second.
- `MeetingControlsPanel`. A `FloatingPanel` subclass that renders the controller's state. It holds no recording state, like `ClipboardPanel`.
- `AppDelegate`. Removes the second status item with the stop button (`KuKa/AppDelegate.swift:282`, `:286-298`).

Public seams for test-driven development: `RecordingClock`, `AudioTrackWriter` with synthetic buffers across a pause, `LiveTranscript`, and the controller's state machine with the existing fake capture.

## Answers from the user

The user answered every design question on 2026-10-27.

1. **Pause in the transcript.** The 3 s silence at each resume is accepted. Ku-Ka writes no `pauses.json`. The times in `transcript.md` are 3 s later than the pill showed for each earlier pause.
2. **Microphone dot during a pause.** The user asked for the simpler option. The stream keeps running during a pause, and Ku-Ka drops the paused buffers. The system dot stays on while the panel says Paused.
3. **Finnish meetings.** No live text for Finnish is needed. A locale that `SpeechTranscriber.installedLocales` does not contain gets no live text.
4. **The second status item.** It goes away when the panel ships. Stop stays in the panel and in the Ku-Ka menu.
5. **Copying from the live text.** Not needed. The transcript text is not selectable.
6. **Quality of the live text.** Apple's quality is good enough for the live view. The final Whisper transcript replaces it at Stop.

## Questions only a measurement can settle

1. Accuracy and latency of the live engine on real meeting audio, with echo and compressed call audio. Generated speech is clean.
2. CPU, Neural Engine, and power cost over a one-hour meeting.
3. Whether 3 s of silence at a pause boundary is enough for the final Whisper pass, and whether Whisper writes a silence phrase into it.
4. Whether a non-activating panel from a menu bar app shows in the Full Keyboard Access and VoiceOver window choosers.
5. What Zoom, Meet, and Teams capture of the panel in a shared screen on macOS 27.

## How this note was made

- Three research agents read the pinned WhisperKit checkout, the macOS 27 Speech SDK with Apple's documentation, and Apple's HIG with AppKit, Live Captions, and Granola's help center. Each claim above was carried over with its citation.
- One agent ran the paced probe with generated speech and the Whisper model already installed in `~/Library/Caches/whisperkit-models`. Nothing was downloaded. The main series ran 5 times per side and the concurrent case 3 times per side, with the sides interleaved. The probe counted errors and empty results and scored the confirmed text of every run against the script. The main session checked the summary lines and the confirmed text in the logs.
- The converter measurement and the mockup were made in a scratch folder outside the repository. The mockup's screenshots cover each layout and state in light mode, and again in dark mode with Reduce Motion on. A screenshot cannot show motion, so Reduce Motion was checked in the browser instead. With it on, the drawer and the pill animate only their opacity, the spinner and the new-line animations stop, and Return to live jumps.
- A reviewer on a different model (Fable 5.1) checked the decision trail, this note, and its citations against the code and the evidence. Its flags were applied to this note.
