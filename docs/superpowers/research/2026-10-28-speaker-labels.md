# Speaker labels in the final meeting transcript

Status update, 2026-10-29: microphone room labels shipped in [PR #45](https://github.com/ChristianVilen/ku-ka/pull/45), after the real-room check recorded in [AGENTS.md](../../../AGENTS.md#meeting-notes-implementation). The shipped settings use threshold 0.6 and no fixed speaker count. Remote speakers still share Them. This note preserves the earlier measurements and proposals; statements about pending review describe the research date.

Research and design, 2026-10-28. No production code is part of this note. The user has not reviewed it yet.

## How to read this note

Each statement has one of five labels.

- **Fact.** A cited source says it: a line in the pinned package, a Ku-Ka line, a web page, or a command.
- **Measured.** It ran on this Mac in this session. The run count is given. The voices are generated with `say`, so they are not real people. See [Caveats](#caveats) for why that can make the accuracy numbers too high or too low.
- **Inference.** It follows from facts or measurements in this note, but nothing tested it directly.
- **Proposal.** It is the author's judgment. The user can change it.
- **Open.** Nobody knows yet. The note says what would settle it.

All measurements ran on an Apple M5 Pro with 18 cores, macOS 27.0.1 (26A434).

Package paths such as `Sources/SpeakerKit/SpeakerKit.swift:57` are in the pinned checkout of https://github.com/argmaxinc/argmax-oss-swift at tag `v1.1.1`, commit `1bbc57cb`. Paths that start with `KuKa/` are Ku-Ka's code at commit `e0d5365`.

## Summary

1. **SpeakerKit is cheap and works offline.** **Fact.** It ships in the package that Ku-Ka already pins. Its model is 11.2 MB under CC BY 4.0, and it loads from a folder with no network. **Measured.** It labels a 5-minute microphone track in 0.49 s and a 60-minute one in 4.7 s (median of 5 runs each). That is 4 to 5% of the time Whisper needs for the same track.
2. **Its labels are often wrong on this test.** **Measured.** On a generated room meeting with three voices on the microphone, 80 to 81% of the words got the right room speaker. On the same meeting looped to 30 minutes, 62% did. Most errors fell between the two female voices and on short replies such as "Fine." Results were the same in every run. Asking for exactly 3 speakers made it worse (53%). A clustering threshold of 0.5 instead of 0.6 gave 77% on both lengths. That is better for the long file and worse for the short one.
3. **Word timestamps are not needed for the first version.** **Measured.** They cost only 0.5% more Whisper time and changed no spoken word. They also bought nothing here. Labelling each whole Whisper segment by its most overlapping speaker gave the same accuracy as SpeakerKit's word-level join, within 1 point.
4. **Proposal. Check real audio before building.** The user runs the research probe on one real room recording and reads the labelled transcript. Generated voices cannot tell whether real colleagues are easier or harder to separate.
5. **Proposal, if the check reads well.** Diarize only the microphone track, inside the transcribe step, before `transcript.md` is written. Label room speakers "Room 1", "Room 2", and so on. Keep "Them" for the call. Never guess which room speaker is the user. Write the transcript as today when anything about speaker labels fails. Add no file and no stage.
6. **Proposal, later.** Name the user "Me" only from a stored voice sample of at least 30 s. **Measured.** A 34 to 40 s sample matched the right speaker for all three voices. An 8 s sample matched the wrong one for all three.

The questions only the user can answer are in [Questions for the user](#questions-for-the-user).

## The problem and the Ku-Ka code it touches

**Fact.** Ku-Ka labels every segment of the microphone track "Me" and every segment of the system track "Them" (`KuKa/MeetingFolder.swift:14-19`). `Transcript.merge` joins one speaker's segments when the gap is under 2 s (`KuKa/Transcript.swift:21-42`). When several people sit in the user's room, all their words come from the microphone. So they all get "Me", and their turns join into one line when they reply within 2 s.

Other code facts that shape the design:

1. **Fact.** `MeetingProcessor.transcribe` loads one transcriber session, transcribes each track, merges, and writes `transcript.md` in one atomic write (`KuKa/MeetingProcessor.swift:86-106`). The stage comes from the files, and `transcript.md` means that transcription finished (`KuKa/MeetingFolder.swift:59-80`). The summarize step moves `audio/` to the Trash (`KuKa/MeetingProcessor.swift:145`).
2. **Fact.** A transcriber that cannot start is recorded as a `TranscriberFailure`, and `transcript.md` names it under the byline ("Tried first:") (`KuKa/MeetingProcessor.swift:108-138`, `KuKa/Transcript.swift:65-69`).
3. **Fact.** Ku-Ka keeps only start, end, and text for each Whisper segment. `TranscriptSegment` has no words (`KuKa/Transcript.swift:3-7`, `KuKa/WhisperKitTranscriber.swift:83-87`). Ku-Ka's decoding options leave word timestamps off (`KuKa/WhisperKitTranscriber.swift:164-167`).
4. **Fact.** The echo rule drops a microphone segment of 3 or more words that overlaps a system segment in time (1 s slack) and shares at least 60% of its words with it (`KuKa/Transcript.swift:44-57`). It works on whole Whisper segments.
5. **Fact.** The summary prompt explains only two labels: "'Me' is the person who recorded the meeting. 'Them' is everyone else on the call, and the transcript does not tell those people apart." Action item owners are "Me, Them, or a name said in the meeting" (`KuKa/MeetingSummarizer.swift:126-136`).
6. **Fact.** `Transcript.contentForSummary` cuts `transcript.md` after the exact legend sentence, so the summary CLI never sees the legend (`KuKa/Transcript.swift:58-63`). A changed legend sentence would not match, and the whole file, with its title and byline, would go to the CLI. A transcript that an older Ku-Ka wrote can still reach the summary step after an update, through launch recovery or Retry.
7. **Fact.** Ku-Ka pins the package at exactly 1.1.1 and links only its `WhisperKit` product (`KuKa.xcodeproj/project.pbxproj:329-330`, `:339`). SpeakerKit is a second product of the same package (`Package.swift:28-30`, `:79-86`). Its target depends on `ArgmaxCore` and `WhisperKit`, so it adds no new package.
8. **Fact.** Another change in this worktree edits `Transcript.merge` now: `joinGap` becomes optional (uncommitted diff of `KuKa/Transcript.swift`). The design below touches the same function.

## SpeakerKit 1.1.1

### API

1. **Fact.** It works offline on a whole file only. `diarize(audioArray:options:progressCallback:)` takes all 16 kHz mono samples as one `[Float]` and returns one `DiarizationResult` (`Sources/SpeakerKit/SpeakerKit.swift:64-71`). Version 1.1.1 has no streaming or incremental API. So it cannot label the live view.
2. **Fact.** The options are in `PyannoteDiarizationOptions` (`Sources/SpeakerKit/Pyannote/PyannoteConfig.swift:129-156`):
   - `numberOfSpeakers`: an exact count, or nil for automatic.
   - `clusterDistanceThreshold`: default 0.6 (`Sources/SpeakerKit/Pyannote/SpeakerClustering.swift:17`).
   - `minActiveOffset`: joins one speaker's segments across short gaps.
   - `useExclusiveReconciliation`: default true, one speaker per frame.
   - `centroidSource` and `clipTimestamps`.
3. **Fact.** There is no minimum or maximum speaker count. `minClusterSize` is declared, but no code in 1.1.1 reads it. `SpeakerClustering.swift:39-45` passes on only the threshold, the count, and the centroid source.
4. **Fact.** With `numberOfSpeakers` set, SpeakerKit clusters automatically first. If the count differs, it clusters again with k-means and a fixed seed (`Sources/SpeakerKit/Pyannote/VBxClustering.swift:100-108`, `ClusteringAlgorithms.swift:134-139`).
5. **Fact.** The result has `segments` (speaker id, start, end), `speakerCount`, and `speakerCentroidEmbeddings`, one mean voice embedding per speaker. SpeakerKit says these centroids can link a speaker across separate runs. It defines no "same speaker" threshold, so the caller must calibrate one (`Sources/SpeakerKit/DiarizationResult.swift:34-53`).

### Joining with WhisperKit

1. **Fact.** `DiarizationResult.addSpeakerInfo(to:strategy:)` labels a WhisperKit transcription (`DiarizationResult.swift:182-191`). `.subsegment`, the default, splits each Whisper segment where two words are more than 0.15 s apart (`Sources/SpeakerKit/SpeakerInfo.swift:13-16`). Each piece gets the speaker with the most overlapping time. `.segment` gives each whole Whisper segment the speaker with the best intersection over union.
2. **Fact.** Both strategies need word timestamps. A segment without words is skipped, with only a log line that says to enable `wordTimestamps` (`DiarizationResult.swift:222`, `:296-302`). Without word timestamps, `addSpeakerInfo` returns no text at all.
3. **Fact.** A piece with no overlapping speaker gets the previous piece's speaker (`DiarizationResult.swift:224`).
4. **Fact.** The CLI's `transcribe --diarization` turns `wordTimestamps` on (`Sources/ArgmaxCLI/TranscribeCLI.swift:142-143`).
5. **Fact.** Word timestamps add a dynamic time warping step after each decoded window. That step also moves the next window's start to the end of the last timed word (`Sources/WhisperKit/Core/TranscribeTask.swift:197-222`). So word timestamps can change where windows start, which can change text. The decoder copies the alignment weights for every token whether word timestamps are on or off (`Sources/WhisperKit/Core/TextDecoder.swift:727-735`).

### Threads and compute units

1. **Fact.** `SpeakerKit` is `@unchecked Sendable`, and `diarize` says "Concurrent callers are safe" (`SpeakerKit.swift:11`, `:57`). Every call makes a new `PyannoteDiarizer` with its own actor and clusterer over the shared loaded models (`Sources/SpeakerKit/SpeakerKitDiarizer.swift:33-36`, `Sources/SpeakerKit/Pyannote/PyannoteModelManager.swift:132-146`).
2. **Fact.** The segmenter runs on the CPU. The embedder runs on the CPU and Neural Engine. The embedder's feature step and the PLDA projection run on the CPU (`PyannoteConfig.swift:11-35`, `SpeakerPreEmbedderModel.swift:14`, `SpeakerEmbedderModel.swift:516`). Four segmenter workers run by default, and up to eight embedder workers by the formula `min(8, max(2, audioSeconds / 30))` (`PyannoteConfig.swift:43-46`, `PyannoteDiarizer.swift:184`).
3. **Fact.** An embedder error is logged and dropped, and diarization goes on without those embeddings (`Sources/SpeakerKit/Pyannote/PyannoteDiarizer.swift:195-200`). A failure in that stage does not reach the caller.

## The model

The size and the license, facts 1 to 3, went into this note before the research download.

1. **Fact.** SpeakerKit downloads from the Hugging Face repository `argmaxinc/speakerkit-coreml` by default (`Sources/SpeakerKit/SpeakerKitConfig.swift:37`, `README.md:597`). The repository was at commit `556fc52a` on 2026-10-28 (`curl https://huggingface.co/api/models/argmaxinc/speakerkit-coreml`).
2. **Fact.** On macOS 15 and later, the loader picks three models (`PyannoteConfig.swift:11-35`). The repository file list gives their sizes (`curl https://huggingface.co/api/models/argmaxinc/speakerkit-coreml/tree/main?recursive=true`):
   - the segmenter `speaker_segmenter/pyannote-v3/W8A16`, 1,718,680 bytes
   - the embedder `speaker_embedder/pyannote-v3/W8A16`, 9,314,949 bytes
   - the clusterer `speaker_clusterer/pyannote-v4/W32A32`, 209,602 bytes

   That is 11.2 MB in total, as compiled `.mlmodelc` folders. Ku-Ka's Whisper model is 1.5 GB (`du -sh` of the installed model).
3. **Fact.** The model card says: "SpeakerKit the Swift framework has MIT license. The models SpeakerKit is built on have CC BY 4 license." Its license tag is `cc-by-4.0`. A README in each model folder points to the original weights:
   - The segmenter to `pyannote/segmentation-3.0`, MIT on Hugging Face.
   - The embedder to WeSpeaker's pretrained models. A model trained on VoxCeleb follows CC BY 4.0 (https://github.com/wenet-e2e/wespeaker/blob/master/docs/pretrained.md#model-license).
   - The clusterer to BUT's VBx, Apache 2.0 (https://github.com/BUTSpeechFIT/VBx).

   The whole `pyannote/speaker-diarization-community-1` pipeline is `cc-by-4.0` on Hugging Face. CC BY 4.0 allows copies, including inside an app, with credit to the source.
4. **Fact.** Without a folder, the hub code downloads into `~/Documents/huggingface` (`Sources/ArgmaxCore/External/Hub/HubApi.swift:105-110`). Ku-Ka already works around the same rule for Whisper (`KuKa/WhisperKitTranscriber.swift:126-127`). `PyannoteConfig` takes `downloadBase` for a download and `modelFolder` for a model that is already on disk (`PyannoteConfig.swift:75-111`).
5. **Fact.** With `modelFolder` set, nothing downloads. The loader returns that folder (`PyannoteModelManager.swift:63-68`), and the model manager skips the download step (`Sources/ArgmaxCore/ModelManager.swift:94-99`). With only `downloadBase`, the manager checks the cached files offline and downloads again when that check fails (`Sources/ArgmaxCore/ModelDownloader.swift:197-233`). The hub writes partial files as `.incomplete` files under the repository's `.cache` folder (`HubApi.swift:531`). It does not use a temporary folder name for the model.
6. **Measured, one download.** `PyannoteConfig(downloadBase:)` downloaded 23 files, 11,243,231 bytes, in 12.3 s into `<downloadBase>/models/argmaxinc/speakerkit-coreml/`. Nothing appeared in `~/Documents/huggingface`.
7. **Measured, every run in this note.** Each run loaded the models with `modelFolder` set, a repository name that does not exist, and the endpoint `http://127.0.0.1:9`. Every load worked. So a model on disk loads with no network.
8. **Measured.** The first load on this Mac took 4.78 s, because Core ML compiles the models for the device (1 run). Later loads took 0.047 to 0.075 s (25 runs).

## Measured: accuracy and cost

### Setup

- **The room meeting.** An invented release-planning meeting, 296.6 s long, with 66 utterances and 821 words. The microphone track has three `say` voices: the user (Samantha, 25 utterances, 87.2 s), room speaker A (Daniel, 15, 58.4 s), and room speaker B (Karen, 15, 60.8 s). Room turns follow each other after 0.2 to 0.8 s, with two overlaps of 0.5 s and 0.4 s. The system track has one remote voice (Rishi, 11 utterances, 57.1 s). Both tracks are 16 kHz mono Int16 CAF, the format that `AudioTrackWriter` writes. A manifest holds each utterance's track, voice, start, end, and text. It is the reference.
- **Longer files.** The same meeting looped 6 times (1,779.5 s) and 12 times (3,558.9 s).
- **SpeakerKit** ran with its defaults unless a table says otherwise, from the scratch model folder.
- **Whisper** ran Ku-Ka's final pass: VAD chunks, 4 workers, no first-token threshold, Ku-Ka's silence filter. It used `large-v3-v20240930_turbo` from `~/Library/Caches/whisperkit-models`, the same variant that Ku-Ka installs.
- **Scoring.** The probe maps each found speaker to at most one voice, by the most shared time. "Words by utterance" gives each reference utterance the speaker with the most time inside it and counts its words. "Words by join" labels Whisper's words through each join strategy and checks each word's midpoint against the reference. The error rates use 10 ms frames and ignore 0.25 s on each side of every reference boundary.

### Accuracy of SpeakerKit on the microphone track

**Measured, 5 runs per column.** Every run gave the same speakers, segments, and scores.

| | 5 minutes | 30-minute loop | 60-minute loop |
|---|---|---|---|
| Speakers found, for 3 voices | 4 | 4 | 4 |
| Words by utterance, right speaker | 84.7% | 63.9% | 63.9% |
| Utterances with the right speaker | 38 of 55 | 214 of 330 | 426 of 660 |
| Short replies (3 words or fewer) right | 1 of 6 | 18 of 36 | 31 of 72 |
| Speaker confusion | 13.0% | 33.8% | 32.5% |
| Diarization error rate | 16.7% | 38.4% | 40.8% |

What went wrong:

- **Measured.** On the 5-minute file, 12 of the 17 wrong utterances were the user (Samantha) labelled as room speaker B (Karen), or B labelled as the user. These are the two female voices. Most were short, such as "Fine.", "Yes, go ahead.", and "What do you mean?". The other 5 went to the fourth speaker, which held 11.1 s of short pieces, 7.5 s of them the user's.
- **Measured.** On the 30- and 60-minute loops, one speaker took in most of the user's and B's speech. On the 30-minute loop, that speaker held 786 s, and the user spoke for 523 s. The audio repeats, so the drop comes from clustering more embeddings of the same voices, not from new voices.
- **Fact, for comparison.** pyannote reports a 19.9% diarization error rate for community-1 on AMI with one distant microphone, and 17.0% with headset microphones. Those numbers use no collar and score overlapping speech (https://huggingface.co/pyannote/speaker-diarization-community-1, "Benchmark").

### Settings

**Measured, 3 runs per cell, 5 for the default and for the exact count.** Words by utterance, with the number of speakers found.

| Setting | 5 minutes | 30-minute loop |
|---|---|---|
| Threshold 0.4 | 82.3%, 4 | 78.4%, 6 |
| Threshold 0.5 | 81.5%, 4 | 79.8%, 6 |
| Threshold 0.6, the default | 84.7%, 4 | 63.9%, 4 |
| Threshold 0.7 | 64.8%, 3 | 64.5%, 3 |
| Threshold 0.8 | 67.7%, 2 | 64.5%, 3 |
| `numberOfSpeakers: 3` | 54.0%, 3 | Not run |

No threshold was best for both lengths. An exact count of 3 made the 5-minute result much worse, because the k-means pass put B's speech with the user's. So, on this test, asking the user how many people are in the room would not help.

### The system track

**Measured, 5 runs.** The system track has one voice. SpeakerKit found 2 speakers. The first two remote utterances, in the first 45 s, became their own speaker. 9 of 11 utterances got the main speaker.

### Joining labels with Whisper's text

**Measured.** Words by join, the share of Whisper's microphone words with the right speaker. The diarization and Whisper outputs were the same in every run of each setting, 3 or 5 runs, and a join is a pure function of them.

| Join | 5 minutes, default | 5 minutes, threshold 0.5 | 30-minute loop, default | 30-minute loop, threshold 0.5 |
|---|---|---|---|---|
| SpeakerKit `.subsegment`, needs word timestamps | 80.3% | 78.5% | 62.1% | 77.6% |
| SpeakerKit `.segment`, needs word timestamps | 81.2% | 76.8% | 62.0% | 76.5% |
| Whole Whisper segment, most overlapping speaker, no word timestamps | 80.6% | 76.8% | 62.0% | 77.2% |
| Words in Whisper segments that hold two voices, `.subsegment` and by overlap | 94 and 95 of 127 | Not counted | 329 and 328 of 630 | 480 and 475 of 630 |

- **Measured.** With `numberOfSpeakers: 3`, the join by overlap gave 52.9% on the 5-minute file.
- **Measured.** 7 of 64 Whisper segments on the 5-minute track held words of two voices. Splitting them by word times did not help, because the speaker errors came from diarization, not from the join.
- **Measured, 5-minute file.** Ku-Ka's merge was replayed with the Them track included. Today, 10 of the 18 microphone lines mix two or more voices, with 575 of 650 words. With labels by overlap, 16 of 38 lines mix voices, with 405 words. A labelled line still mixes voices when one Whisper segment holds two voices, or when two voices get the same label.

### Which room speaker is the user

- **Measured.** The speaker with the most speech mapped to the user in every run of the 5-, 30-, and 60-minute files. This is no evidence for the rule. The script gives the user 42% of the room speech, and on the loops that speaker also held most of B's speech.
- **Measured, voice sample of one sentence.** A new sentence in each room voice, 7.6 to 8.2 s long, was diarized alone. Its centroid was compared with the meeting's centroids by cosine distance. For all three voices, the nearest meeting speaker was the small fourth speaker (distances 0.095 to 0.201), not the right one (0.500 to 0.710). 2 rounds, identical.
- **Measured, the same sample repeated to 34 to 40 s.** Each voice was nearest to its own speaker. The table gives the distance to the right speaker and to the next nearest one. 2 rounds on the 5-minute result, identical, and 1 round on the 30-minute result with threshold 0.5.

| Sample | 5 minutes: right, next | 30-minute loop: right, next |
|---|---|---|
| The user (Samantha) | 0.093, 0.278 (B) | 0.101, 0.293 (B) |
| Room speaker A (Daniel) | 0.299, 0.792 | 0.246, 0.657 |
| Room speaker B (Karen) | 0.086, 0.389 (user) | 0.072, 0.394 (user) |

**Inference.** A short sample fills only a small part of SpeakerKit's 30 s segmenter chunk (`SpeakerSegmenterModel.swift:20`), and its embedding looks like other mostly silent windows. A sample needs about 30 s of speech. The smallest margin is between the two female voices.

### Cost

**Measured, 5 runs per cell, alternated.** Median and range of the `diarize` call. The process figures cover the whole process, including the load.

| | 5 minutes | 30-minute loop | 60-minute loop |
|---|---|---|---|
| `diarize` time | 0.49 s [0.44 to 0.51] | 2.35 s [2.14 to 2.39] | 4.69 s [4.27 to 4.83] |
| Per minute of audio | 0.10 s | 0.08 s | 0.08 s |
| CPU time over wall time | 2.7 to 3.0 s over 0.5 to 0.6 s | 16.4 to 17.9 s over 2.3 to 2.5 s | 33.8 to 36.5 s over 4.4 to 5.0 s |
| Peak memory of the process | 509 to 575 MB | 905 to 942 MB | 1,355 to 1,376 MB |
| Segmenter chunks, embeddings | 14, 472 | 85, 2,878 | 170, 5,757 |
| Clustering time | 5 ms | 64 ms | 280 ms |

- A second series of 5 default runs on the 30-minute loop gave 2.17 s [2.14 to 2.20].
- Time grows in proportion to the audio. Clustering grows faster, but stays under 0.3 s for an hour.
- Memory grows with the audio. An hour of samples as `[Float]` alone is 228 MB.
- No run failed. All 90 timed runs exited with status 0 and wrote their output.

**The limiting resource. Measured, 5 runs each on the 30-minute loop, alternated, same accuracy in all.**

| Compute units | `diarize` time |
|---|---|
| Defaults: segmenter on CPU, embedder on CPU and Neural Engine | 2.17 s [2.14 to 2.20] |
| Embedder on CPU only | 4.00 s [3.80 to 4.00] |
| Embedder on CPU and GPU | 2.16 s [2.10 to 4.67] |
| Segmenter on CPU and Neural Engine | 24.50 s [24.45 to 24.85] |

The work is bound by the CPU. About 7 of the 18 cores are busy during `diarize`, mostly in the embedding stage. The defaults are already the fastest choice measured.

**Word timestamps. Measured, 5 runs per cell, alternated, microphone track.**

| | 5 minutes | 30-minute loop |
|---|---|---|
| Whisper, word timestamps off | 10.10 s [10.09 to 10.10] | 61.78 s [61.76 to 61.79] |
| Whisper, word timestamps on | 10.15 s [10.14 to 10.16] | 62.06 s [62.05 to 62.09] |
| Difference | +0.05 s, 0.5% | +0.28 s, 0.5% |
| Alignment step, summed over 4 workers | 0.25 to 0.27 s in 20 windows | 1.50 to 1.51 s in 123 windows |

- **Measured.** The spoken words were the same with word timestamps on and off. The only differences were phrases that Whisper writes over silence. On the 5-minute track, "off" wrote an extra "you", and "on" wrote an extra "Thank you." On the 30-minute loop, "off" wrote 10 "you" and 5 "Thank you.", and "on" wrote 4 "Thank you.". Each side gave the same text in all 5 runs.
- **Measured.** Whisper used 0.25 to 0.32 of a CPU core and 330 to 660 MB of process memory, with word timestamps on or off. Its limit is the Neural Engine, as the [floating panel note](2026-10-27-floating-meeting-panel.md) found.
- So on the 30-minute microphone track, diarization costs 2.2 to 2.4 s next to 62 s of Whisper. Word timestamps would add 0.3 s more.

### Caveats

- Generated voices do not cover what makes real rooms hard: distance from the microphone, room echo, people who talk over each other for long, and laptop-speaker echo of the call. These can make accuracy worse.
- The speaker embedder was trained on recordings of real people (VoxCeleb). Generated voices can sit closer together or further apart in its space than real colleagues do. So these numbers are not an upper limit, unlike the transcription numbers of the floating panel note.
- The loops repeat one 5-minute meeting. A real hour has more variety in each voice.
- The test has one pair of similar voices. A room of three men, or three women, was not tested.

## Design

### Where diarization runs

| | A. Microphone track, inside the transcribe step | B. Both tracks, inside the transcribe step | C. A new step after `transcript.md` |
|---|---|---|---|
| What gets labels | People in the room | People in the room and on the call | Either |
| Stage rule | Unchanged | Unchanged | Needs a new file and stage, or a rewrite of `transcript.md` |
| Cost per hour of audio | About 5 s | About 10 s | Same as A or B |
| Crash during diarization | No `transcript.md` yet, so the whole step runs again | Same | The new stage needs its own recovery |
| Risk | Similar room voices merge | Also, on this test, one remote voice came back as two speakers | More states to test |

**Proposal: A.** Diarize the microphone track inside `MeetingProcessor.transcribe`, after both tracks are transcribed and before `transcript.md` is written. Diarization costs seconds, so a separate step with its own file buys nothing. Leave the system track as "Them". The user's problem is the room, and on this test the one remote voice came back as two speakers.

Order inside the step:

1. Transcribe both tracks as today. Keep word timestamps off.
2. Release the Whisper session, so the two models are not in memory at the same time.
3. Load SpeakerKit and diarize `me.caf`.
4. Apply the echo rule to whole microphone segments, as today.
5. Give each remaining microphone segment the room speaker with the most overlapping time. This is a small pure function in Ku-Ka. It replaces `addSpeakerInfo`, which needs word timestamps.
6. Merge as today. The 2 s join joins only lines with the same label.
7. Write `transcript.md` once, atomically, as today.

Word timestamps and `.subsegment` stay an option. They cost 0.5% and changed no spoken word, but they gave no measured gain. Turn them on only if real audio shows many Whisper segments with two voices.

### How the labels look

`transcript.md` lines keep their form, `**[00:01:23] Label:** text`. The question is what the room labels say, and which one is the user.

| | Neutral labels | The dominant speaker is "Me" | A voice sample at first use |
|---|---|---|---|
| Example | `Room 1`, `Room 2`, `Room 3`, `Them` | `Me`, `Room 2`, `Room 3`, `Them` | `Me`, `Room 2`, `Room 3`, `Them` |
| Which one is the user | Nobody says | The speaker with the most speech | The speaker nearest to the user's stored voice |
| When it is wrong | It never names the user | When the user talks less than someone else, "Me" is a colleague | When the user's voice merged with another voice, "Me" includes that person |
| New UI | None | None | A one-time recording of about 30 s, and a way to record again |
| New stored data | None | None | One voice embedding, on this Mac only |

**Proposal.** Start with neutral labels for the room and "Them" for the call. Do not use the dominant-speaker rule. It needs no work, but the measurement could not test it, and a wrong "Me" misleads more than a neutral label. Add the voice sample later, if the user wants "Me" back. Its match threshold must come from real voices, because SpeakerKit defines none.

- When diarization finds one speaker on the microphone track, that speaker is "Me", as today.
- Number the room labels in order of first speech, so "Room 1" opens the meeting.
- The legend under the byline says that room labels come from voice matching, can mix two people with similar voices, and can split one person.
- The summary prompt changes with the labels. It explains "Room N" as people in the same room as the person who recorded, and says that one of them is that person. It says to take an action item owner from the text when the text names one, and not from a room label alone. It keeps the old "Me" and "Them" text for transcripts that an older Ku-Ka wrote. `contentForSummary` must cut both the old and the new legend.

Example of the proposed lines, from the probe's `label` mode on the generated meeting:

```
**[00:00:00] Room 1:** Good morning, everyone, let's start. We have three things today: ...
**[00:00:09] Room 2:** Before we start, can we also talk about the on-call rotation for next month? It is still empty.
**[00:00:16] Room 3:** Yes, let's add it at the end. I also have two design questions about the settings page, ...
```

The third line shows the main error. The user's "Yes, let's add it at the end." went to B's label.

### When the model is missing or fails

**Proposal.** Speaker labels never block the transcript. Like the transcriber fallback, the transcript names what failed under the byline.

- If the model is missing, cannot download, or cannot load, or if `diarize` throws, Ku-Ka writes `transcript.md` with "Me" and "Them" as today. It adds one line under the byline, such as "Speaker labels: not available. SpeakerKit could not load its model: <message>."
- If `diarize` returns no segments while Whisper found speech on the microphone track, Ku-Ka treats it as a failure, with the same result. SpeakerKit drops embedder errors without telling the caller, so an empty result is the only sign of one.
- A missing model never fails the transcribe step and never writes `error.md`.
- Cancellation (quit) stays cancellation. It writes nothing and marks nothing failed.

### Getting the model onto the Mac

| | Download at first use | Ship it inside Ku-Ka.app |
|---|---|---|
| Size | 11.2 MB download | 11.2 MB more in the app |
| Network | Once | Never |
| New states | Partial folder, lock, a failed download | None |
| License | Credit CC BY 4.0 in the app | Same, and the files live in the repository or a build step fetches them |
| Model update | A new folder for each pinned revision | Comes with an app update |

**Proposal.** Download at first use, the way Ku-Ka installs Whisper. Use `~/Library/Application Support/Ku-Ka/speaker-models/<revision>/`, written as `.<revision>.partial/` and renamed when complete, under the existing `FileLock` pattern (`KuKa/WhisperKitTranscriber.swift:27-43`). Pass `downloadBase` for the download, pin `downloadRevision` to a commit, and load with `modelFolder`. The download took 12.3 s here. It can run in the transcribe step under the existing "Downloading speech model" text. Shipping the model in the app is simpler at run time, and it is the better choice if the user accepts 11 MB of model files in the repository.

### Crash recovery and the stage rule

- **Proposal.** No new file and no new stage. `transcript.md` still means "transcription finished", now with labels or with a line that says why there are none. The audio stays until the summarize step, as today.
- A crash or quit during diarization leaves no `transcript.md`. The next launch runs the transcribe step again from the audio. That costs a second Whisper pass, which already happens today after a crash during transcription.
- Meetings transcribed before the change keep "Me" and "Them". A Retry of such a meeting goes to the summary step and never diarizes.

### Echo and the 2 s join

- **Proposal.** Keep the echo rule on whole Whisper segments, before labels. The rule needs 3 or more words, and it works best on full segments.
- Echo that the rule misses gets a room label instead of "Me". That is no worse than today.
- **Open.** On laptop speakers, the remote voice in `me.caf` may form its own room speaker, or it may pull two room voices together. The generated meeting has no echo. A test file with mixed-in echo would settle it.
- Keep the 2 s join, and join only lines with the same label. Two room speakers who reply within 2 s then get separate lines.

## Recommendation

1. **Proposal. Measure real audio first.** The user records one short meeting in the room, takes `audio/me.caf` back from the Trash, and runs the probe's `label` mode on it. The command writes a labelled transcript to a file of the user's choice and sends nothing off the Mac:

   ```bash
   spk label <path to me.caf> <model folder>/models/argmaxinc/speakerkit-coreml <output.md>
   ```

   The probe and the model live in this session's scratch folder, in `speaker-research/`. The system can clean that folder at any time, so the check works only while it exists.
2. **Proposal. If the labels read well,** build design A with neutral labels, the segment-level join, no word timestamps, the failure rules above, and the model download. TDD seams: the pure join function, the label naming and the legend in `Transcript.markdown`, the summary prompt and `contentForSummary` with old and new transcripts, and `MeetingProcessor` with a fake diarizer that is missing, throws, returns nothing, and returns speakers.
3. **Proposal. If they read badly,** stop here. The generated test already shows that similar voices merge, and no setting fixed both file lengths.
4. **Later, and only if wanted.** Add the voice sample for "Me", with a threshold measured on real voices.

## Questions for the user

1. Who usually sits in the room, and are their voices alike? Two similar voices were the main error on this test.
2. Is "Room 1", "Room 2" good enough, with no "Me" for the room? Or should Ku-Ka learn the user's voice from a one-time sample of about 30 s?
3. Should remote people ("Them") also be told apart? Not proposed now. The one remote voice was split in two on this test.
4. Download the 11 MB model at first use, or ship it inside the app with the files in the repository?
5. Where should the CC BY 4.0 credit go: an acknowledgements file, the About window, or both?
6. How should the summary use room labels for action items? The proposal takes owners from the text only.
7. Will you run the `label` check on one real room recording before any code is written?

## Questions only a measurement can settle

1. Accuracy on real room audio, with real distance, room echo, and laptop-speaker echo of the call.
2. Whether the default threshold of 0.6 suits a real hour-long meeting. On the generated loops, 0.5 did better.
3. A match threshold for the voice sample on real voices.
4. How echo in `me.caf` changes the room speakers.

## How this note was made

- One agent read the pinned checkout (SpeakerKit, ArgmaxCore's downloader and hub code, and WhisperKit's word timestamps), Ku-Ka's code at `e0d5365`, the model repository through the Hugging Face API, and the license pages that the model folders link to.
- A throwaway Swift package in the scratch folder, not Ku-Ka code, generated the audio and ran SpeakerKit and WhisperKit from the same pinned checkout as Ku-Ka. Release build. The SpeakerKit model was downloaded into the scratch folder only.
- Each run was a separate process under `/usr/bin/time -l`. Before each run, the script waited while any `xcodebuild` ran, because another agent ran tests on this Mac. All timed runs started after Ku-Ka had finished transcribing a meeting. The load averages at the start of the runs were 0.4 to 7.2. The sides of each comparison ran alternated.
- No microphone or system audio was recorded. No real meeting was read.
