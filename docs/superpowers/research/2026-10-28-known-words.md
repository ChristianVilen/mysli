# Known words for meeting notes

Research and design, 2026-10-28. No production code is part of this note. Nothing ran on audio, and no model was loaded. The user has not reviewed this note yet.

The request: a list of known names and terms that Ku-Ka keeps learning from. Ku-Ka asks the user when a sentence looks wrong, so that the next meeting notes spell those words right.

## How to read this note

Each statement has one of three labels.

- **Fact.** A cited source says it: a repository line, a WhisperKit line, an SDK line, a web page, a paper, or a command that ran in this session. No command touched audio or loaded a model.
- **Proposal.** It is the author's judgment. The user can change it.
- **Open.** Nobody knows yet. The note says what would settle it.

Citations:

- Ku-Ka paths are at commit `e0d5365`.
- Paths that start with `Core/` are under `Sources/WhisperKit/Core/` in the pinned WhisperKit checkout, tag `v1.1.1`, commit `1bbc57cb` (https://github.com/argmaxinc/argmax-oss-swift/tree/v1.1.1). Other WhisperKit paths start at its repository root.
- `SI:line` is a line in `Speech.framework/Versions/A/Modules/Speech.swiftmodule/arm64e-apple-macos.swiftinterface` in the macOS 27 SDK of the installed Xcode.
- "Decoder metadata" is `TextDecoder.mlmodelc/metadata.json` of the model that Ku-Ka installed in `~/Library/Application Support/Ku-Ka/whisper-models/`. It was read with `jq`, without a model load.
- "The earlier research note" is [Floating meeting recorder panel](2026-10-27-floating-meeting-panel.md).

The error patterns below come from a real English meeting. This repository is public, so this note replaces every real person, company, and repository name with an invented one that has the same kind of error. Public product names stay.

## Summary

1. **Recognition bias is not ready for a first version.** **Fact.** WhisperKit keeps only the last 111 prompt tokens, puts the same prompt before every 30 s window, and makes the prompt share the window's 224-token budget with the text. A prompt leaked into the transcript when Ku-Ka tried one. A study found that a plain word list in Whisper's prompt helped rare words but hurt all other words. Apple's contextual strings work only with `DictationTranscriber`, and Ku-Ka uses `SpeechTranscriber` for both the live text and the fallback.
2. **Proposal. The first version fixes text, not recognition.** Ku-Ka replaces confirmed misheard forms with the right form, word by word, in the transcript, in the text for the summary, and in the live view.
3. **Proposal. The summary prompt gets the known words.** The summary CLI can match a new misspelling to a known word by sound and context, which a fixed replacement cannot do. The same call returns a short machine-readable list of words that look misheard.
4. **Proposal. Ku-Ka asks after the notes are ready, not during the meeting.** A small review window shows each suspect sentence with suggestions. Each answer becomes an entry. Only the user's answers change the list.
5. **Proposal. The list is one Markdown file, `known-words.md`, in the meetings folder.** It follows the user's own correction map: a confirmed line (✓) is fixed without a question, and a line without ✓ makes Ku-Ka ask. Ku-Ka writes it atomically under a `FileLock`.
6. **Later.** Whisper token probabilities as a second, local source of suspects. A short Whisper prompt only after a measurement shows no leak. Audio playback of a suspect sentence only if the user changes the audio rule. `DictationTranscriber` with contextual strings for the live view.
7. **Proposal. Two small fixes that are not about known words.** The summary prompt makes "Me" and "Them" task owners, but several people share each label. The prompt and the transcript describe "Me" as one person.

The questions for the user are in [Questions only the user can answer](#questions-only-the-user-can-answer).

## What goes wrong today

**Fact, as the main session reported it.** These are the patterns from the reviewed meeting, with invented names.

- A coined company name, here "Konvio", came out in six spellings: "Convio", "Konvia", "Gonvio", "Kon Vio", and the real words "Convoy" and "Conveyor". The summary CLI picked one wrong spelling and used it everywhere.
- A person's name, here "Ravindra", came out four ways, once as a two-word fake surname. Another name, here "Maikki", came out five ways, once as ordinary words ("my key").
- Finnish first names in English speech changed: here "Jyri" became "Yuri" and "Iida" became "Ida".
- A hyphenated repository name, here `acme-ops-docs`, became "acme-opsdocks", and the summary repeated the wrong form. A Finnish company name spelled with "k" became the English word with "c", here "Kompassi" became "Compass".
- Product and work terms changed: "Figma" became "Vigmo", and "error states" became "arrow states" and "erostages".
- Whisper also wrote filler lines such as "I I I" and a lone "I".
- In the summary, many action items had the owner "Me" or "Them". Several people in the recorder's room speak on the "Me" track.

So a first version must handle many variants for one term, variants that are real words, names in two languages, hyphenated names, and the summary step, where one wrong spelling spreads.

## Code facts that shape the design

1. **Fact.** Whisper gets no prompt. `WhisperKitLibrary.decodingOptions` sets no `promptTokens` (`KuKa/WhisperKitTranscriber.swift:159-167`), and a test checks it (`KuKaTests/WhisperKitTranscriberTests.swift:86-91`).
2. **Fact.** The reason is recorded only as a result. The commit message of `064a768` says "On real audio, a prompt leaked into the text", and `AGENTS.md:443` says "the prompt's words leaked into the transcript when measured". The repository does not keep the prompt text, its length, its form (a list or a sentence), or which meeting it ran on.
3. **Fact.** The transcribe step merges both tracks and writes `transcript.md` (`KuKa/MeetingProcessor.swift:86-106`). The summarize step moves the audio to the Trash first (`:140-148`), then reads the transcript through `Transcript.contentForSummary` (`:149`) and runs the CLI (`:150`). So the audio is gone before any summary output exists.
4. **Fact.** `SummaryPrompt.make` is one string (`KuKa/MeetingSummarizer.swift:123-149`). It says "Me" is "the person who recorded the meeting" (`:126-128`) and that an owner is "Me, Them, or a name said in the meeting" (`:136`). `agy` gets the prompt as a command-line argument and `claude` gets it on stdin (`:28-33`). `ARG_MAX` is 1 MB (`AGENTS.md:461`).
5. **Fact.** There are two speaker labels. The microphone track is "Me" and the system track is "Them" (`KuKa/MeetingFolder.swift:14-25`). The transcript's legend repeats the one-person wording (`KuKa/Transcript.swift:58`), and `contentForSummary` uses that exact legend to find where the spoken content starts (`:60-63`).
6. **Fact.** Text files are written with `.atomic` (`KuKa/MeetingFolder.swift:152-155`). `FileLock` is an exclusive, non-blocking `flock` (`:206-228`). `MeetingFolder.lock()` uses it (`:177-183`).
7. **Fact.** The stage comes only from audio, `transcript.md`, `summary.md`, and `error.md` (`KuKa/MeetingFolder.swift:52-80`). Another file in a meeting folder does not change the stage. The meeting listing keeps only folders and skips hidden files (`:126-129`), so a file at the root of the meetings folder is not a meeting.
8. **Fact.** The live text uses `SpeechTranscriber` with `.progressiveTranscription` (`KuKa/LiveTranscriber.swift:100`). The fallback transcriber uses `.transcription` (`KuKa/MeetingTranscriber.swift:55`, `:74`). `LiveTranscript` is a pure value in memory (`KuKa/LiveTranscript.swift:49-55`).
9. **Fact.** "Meeting Notes Ready" opens `summary.md` on click (`KuKa/MeetingNotesController.swift:488`). `Notifying.post` takes one URL (`KuKa/Notifier.swift:9`).
10. **Fact.** The meetings folder comes from the `meetingsFolder` setting, default `~/Meetings` (`KuKa/Settings.swift:51-57`), and Ku-Ka reads it at each use.

## Whisper and WhisperKit 1.1.1

### How a prompt reaches the decoder

1. **Fact.** `DecodingOptions` has `promptTokens`, "the conditioning prompt for the decoder", and `prefixTokens`, "the initial prefix for the decoder" (`Core/Configurations.swift:153-154`, `:180-181`).
2. **Fact.** The prefill is `<|startofprev|>`, the prompt, then start of transcript, language, task, and timestamp, then the prefix (`Core/TextDecoder.swift:176-218`). The prefix is the forced start of the output text, so it cannot carry a word list.
3. **Fact.** WhisperKit keeps only the last 111 prompt tokens. The limit is `(Constants.maxTokenContext / 2) - 1` with `maxTokenContext = 448 / 2 = 224` (`Core/TextDecoder.swift:199-200`, `Core/Models.swift:1340`). Earlier tokens are dropped without a message.
4. **Fact.** The prompt and the output share one 224-position cache. The installed decoder's `key_cache` has the shape `[1, 5120, 1, 224]` (decoder metadata). The decode loop stops at `maxTokenContext - 1` tokens, prefill included (`Core/TextDecoder.swift:580`, `:689`). Without a prompt, the prefill is 4 tokens. With a full 111-token prompt, it is 116, which leaves 107 tokens for the text and timestamps of a 30 s window.
5. **Fact.** OpenAI's reference code works differently. It keeps the last `n_ctx // 2 - 1` prompt tokens and samples up to `n_text_ctx // 2` tokens (https://github.com/openai/whisper/blob/main/whisper/decoding.py, `DecodingTask.__init__` and `_get_initial_tokens`). OpenAI's guides say "only the final 224 tokens of the prompt will be considered" (https://developers.openai.com/cookbook/examples/whisper_prompting_guide). In WhisperKit, the limit is half of that, and the prompt also takes room from the output.
6. **Fact.** When a window's tokens end without a timestamp, the seek moves past the whole window (`Core/Text/SegmentSeeker.swift:140-148`).
7. **Open.** Whether a long prompt cuts off fast speech. A window of dense speech can need more than 107 tokens. The measurement plan counts windows that reach the limit.
8. **Fact.** The same prompt goes before every window. `prefillDecoderInputs` runs once (`Core/TranscribeTask.swift:90-92`), and `reset` clears only the cache masks (`Core/Models.swift:312-321`). Ku-Ka's VAD path decodes every chunk with the same options (`KuKa/WhisperKitTranscriber.swift:184-191`). In OpenAI's `transcribe`, `initial_prompt` is "a prompt for the first window", unless `carry_initial_prompt` is set (https://github.com/openai/whisper/blob/main/whisper/transcribe.py).
9. **Fact.** WhisperKit has no "condition on previous text" option. A search of the sources for it finds nothing. OpenAI's code drops the previous text when a window needed a temperature above 0.5 (`prompt_reset_since`, same `transcribe.py`). WhisperKit keeps the prompt in its temperature fallback, because the fallback only calls `reset` (`Core/TranscribeTask.swift:395-401`). Ku-Ka keeps the library's fallback defaults: up to 5 fallbacks, a log probability threshold of -1.0, and a compression ratio threshold of 2.4 (`Core/Configurations.swift:197`, `:213-214`).
10. **Fact.** `whisperkit-cli` encodes a space plus the prompt text and drops special tokens (`Sources/ArgmaxCLI/TranscribeCLI.swift:161-166`). The tokenizer is public (`Core/WhisperKit.swift:28`).

### What OpenAI says about names in a prompt

1. **Fact.** The OpenAI cookbook has a section "Pass names in the prompt to prevent misspellings". It says "A spelling guide can tell the model how to spell names of people, products, companies, etc." It also says the model "follows the style of the prompt, rather than any instructions contained within", that "These techniques are not especially reliable", and that "when prompts are short, Whisper may be less reliable at following their style" (https://developers.openai.com/cookbook/examples/whisper_prompting_guide).
2. **Fact.** OpenAI's speech-to-text guide offers a second method: "A text model can correct misspellings and handle longer terminology lists than Whisper's 224-token prompt window" (https://developers.openai.com/api/docs/guides/speech-to-text, "Post-processing with a text model").
3. **Fact.** Jogi et al. put a plain biasing list in Whisper Large's prompt. The error rate on rare words fell from 23.7% to 18.0%. The error rate on all other words rose on all 11 datasets, and the overall error rate rose on 6 of 11. The authors say the reason is that "Whisper's prompt expects the transcription of the previous speech segment rather than a list of biasing words" (https://arxiv.org/html/2502.11572v2, Section 6, Table 1). The study did not use the turbo model that Ku-Ka uses.

### Known failure modes

1. **Fact.** Whisper writes phrases over silence. Ku-Ka measured 99 "Thank you." segments on one track of a 66-minute meeting (`AGENTS.md:447`). Koenecke et al. found whole invented phrases or sentences in "roughly 1%" of transcriptions, more for speakers with "longer shares of non-vocal durations" (https://arxiv.org/abs/2402.08021).
2. **Fact.** Ku-Ka's own prompt leaked into the transcript (code fact 2). One forum post, not a study, reports loops that repeated names from a prompt in 80% of runs (https://community.openai.com/t/whisper-prompt-leads-to-hallucinations/174896).
3. **Fact.** OpenAI's docstring for `condition_on_previous_text` says that text before the window makes the model "more prone to getting stuck in a failure loop, such as repetition looping" (`transcribe.py`). A prompt is text before the window too.
4. **Proposal, from facts 8 and 9 above.** In Ku-Ka, a prompt would be at its riskiest. It goes before every VAD chunk, also a chunk with a long silence, and it stays in place when a looping window is decoded again.

### Is a names-only prompt different from what failed?

**Open.** Nobody knows what Ku-Ka tried, so nobody knows if a different prompt would behave differently. The sources point both ways. OpenAI recommends a spelling guide with names. The study found that a plain list hurts the other words. The cookbook says Whisper copies the style of the prompt, and a bare list is not the style of a transcript. The prompt text, its form, and its length from the earlier test would settle part of this. The measurement plan settles the rest.

**Proposal.** No Whisper prompt in the first version. If a later measurement shows better names and no leak, use one short sentence of names in transcript style, for example "Ravindra, Maikki, and Jyri talked about Konvio and acme-ops-docs.", with the most-used names only. Add a check that flags a segment made only of prompt words.

### Confidence signals

1. **Fact.** Each `TranscriptionSegment` has `tokens`, `tokenLogProbs`, `avgLogprob`, `compressionRatio`, `noSpeechProb`, and optional `words` (`Core/Models.swift:574-586`).
2. **Fact.** `noSpeechProb` is always 0. The decoder sets `let noSpeechProb: Float = 0 // TODO: implement no speech prob` (`Core/TextDecoder.swift:821`). That explains why `AGENTS.md:447` measured 0 for every segment.
3. **Fact.** `avgLogprob` is one value for the whole 30 s window. Every segment of a window gets the window's average (`Core/Text/SegmentSeeker.swift:132`, `:176`). The average also counts the forced prefill tokens after the start token, each with a log probability of 0 (`Core/TextDecoder.swift:572`, `:802-805`). That explains why `AGENTS.md:447` found the same value, about -0.2, for silence phrases and for real speech.
4. **Fact.** Token log probabilities are real and belong to each segment (`Core/Text/SegmentSeeker.swift:112`). The tokenizer can group a segment's tokens into words with the public `splitToWordTokens` (`Core/Models.swift:1162`). So Ku-Ka can score each word from data it already gets, without the alignment pass.
5. **Fact.** With `wordTimestamps`, `WordTiming.probability` is `exp` of the mean token log probability of the word (`Core/Text/SegmentSeeker.swift:394-402`), rounded to two decimals (`:598`). It needs the decoder's alignment weights. The installed decoder has the output `alignment_heads_weights` (decoder metadata). The earlier research note says word timestamps add an alignment pass per window.
6. **Open.** Whether a misheard name gets a low token probability. A wrong name that is a common word, such as "Convoy", can get a high one. `AGENTS.md` measured `noSpeechProb` and `avgLogprob` only, and fact 2 and fact 3 show that neither of them can carry this signal.

## Apple Speech in the macOS 27 SDK

1. **Fact.** `AnalysisContext` has `contextualStrings`, a dictionary from `ContextualStringsTag` to `[String]` with a predefined `general` tag, and `userData` (SI:482-505). `SpeechAnalyzer` takes a context at init (SI:230, SI:340) and has `context` and `setContext(_:)` (SI:250-253).
2. **Fact.** Apple's page for `contextualStrings` names only `DictationTranscriber`. It says to keep phrases to "one or two words whenever possible" and to "Limit the total number of phrases across all tags to no more than 100". For made-up words, "the system may not estimate their pronounciation correctly", and a custom language model through `customizedLanguage(modelConfiguration:)` can give pronunciations (https://developer.apple.com/documentation/speech/analysiscontext/contextualstrings).
3. **Fact.** In an accepted answer of January 2026, the forum account Apple_Agent wrote: "currently, contextual strings only help transcriptions from the `DictationTranscriber` module. The `SpeechTranscriber` module does not currently take contextual strings into account" (https://developer.apple.com/forums/thread/811083). An answer of September 2025 says the same (https://developer.apple.com/forums/thread/801877). The page does not say that the account is an Apple employee.
4. **Fact.** `DictationTranscriber` has the content hint `customizedLanguage(modelConfiguration:)` (SI:91-95). The earlier research note measured that it supports fi-FI and that the fi-FI asset is not installed.
5. **Open.** Whether `SpeechTranscriber` on macOS 27 still ignores contextual strings. The measurement plan checks it. Until then, contextual strings would do nothing for Ku-Ka, which uses `SpeechTranscriber` everywhere (code fact 8).
6. **Fact.** `SpeechTranscriber` can add a confidence to its text with the attribute option `transcriptionConfidence` (SI:393-395). The value is a `Double` (SI:194-198). Apple describes it as "A confidence level (0–1) of the associated transcription text" (https://developer.apple.com/documentation/foundation/attributescopes/speechattributes/confidenceattribute). Apple does not document whether one value covers a word or a longer run (**Open**). The reporting option `alternativeTranscriptions` fills `Result.alternatives` (SI:379, SI:433).
7. **Fact.** No preset turns on `transcriptionConfidence`. Only the two "WithAlternatives" presets turn on alternatives. `.transcription` and `.progressiveTranscription`, the two presets that Ku-Ka uses, have neither. Command: a Swift script in the scratch folder that prints each preset's `transcriptionOptions`, `reportingOptions`, and `attributeOptions` (`swift presets.swift`, run once). It used no audio and no model.

## A correction convention to follow

**Fact.** The user already keeps a correction map in Markdown for another tool. Its convention:

- Entries are grouped under headings by kind, for example companies, product terms, and people.
- Each line lists the misheard forms, separated by " / ", then an arrow and the right form in bold. A line ends with "✓ confirmed" and a date, or with "provisional".
- Confirmed lines are fixed without a question. A provisional line is only a flag.
- Some lines are notes, not replacements.
- When the user confirms a new mistake, it is added with ✓, so the same mistake does not come back.

**Proposal.** Ku-Ka's list follows the same idea: confirmed lines fix, other lines ask, and a "correct as heard" section works as the guard. It also uses the same Markdown shape, so one person can read both files in the same way.

## Where known words can act

The table repeats the facts above. Only its last row is a proposal.

| | Whisper prompt | Apple contextual strings | Fixed replacement | Known words in the summary prompt | Questions to the user |
|---|---|---|---|---|---|
| What it changes | What Whisper hears | What Apple hears | Text after recognition | The summary text | The list |
| Catches a new misspelling | Maybe | Maybe, with `DictationTranscriber` only | No, only forms it already knows | Yes, by sound and context | Yes |
| Main risk | Leaks into silence, worse text for other words, less room in each window | No effect with `SpeechTranscriber` | A real word replaced by mistake | The CLI "corrects" a word that was right | Too many questions |
| Size limit | 111 tokens | 100 phrases | None | The 1 MB argument limit for `agy` | The user's patience |
| Finnish | Yes | Not installed | Yes | Yes | Yes |
| Evidence | Ku-Ka's prompt leaked. The study shows a cost to other words | Apple's forum answer | Same idea as the user's skill | OpenAI's guide recommends a text model for long term lists | The user's skill |
| First version | No | No | Yes | Yes | Yes |

**Proposal.** Start at the text end. The fixed replacement and the summary prompt need no change to recognition and no measurement on the Neural Engine. They also act at the step where a wrong spelling spreads.

## Fixed replacement

**Proposal.** A pure `Corrector` that takes the list and a text and returns the corrected text and the replacements it made. Rules:

1. Only confirmed (✓) forms are replaced. Other forms create a question.
2. Matches cover whole tokens. A token is a run of letters, digits, apostrophes, and hyphens, so "acme-opsdocks" is one token and "error" inside "errors" is not a match. A form of several words, such as "Kon Vio" or "my key", matches the same tokens with any whitespace between them.
3. The match ignores case. Ku-Ka writes the right form as the list spells it, and keeps an English possessive "'s" after it. Both sides are normalized to Unicode NFC first. Diacritics must match: when Whisper writes a name without them, that form goes in the list as its own variant.
4. Longer forms go first. Replacement runs once over the text and never looks at text that it already replaced, so one entry cannot feed another.
5. A form that is a correctly spelled word of the meeting language, such as "Convoy", "Compass", or "my key", never becomes automatic. Ku-Ka checks this with `NSSpellChecker` when the user confirms an answer, and the line stays a question line. **Open.** How `NSSpellChecker` judges names and Finnish words.
6. A Finnish name with a case ending, such as "Konviolle", is its own token. In the first version, each inflected form is its own variant, learned from an answer. **Open.** A suffix rule for Finnish case endings, for names only, is a later step.
7. Ku-Ka applies the corrector to the merged lines before it writes `transcript.md`, to the text it sends to the summary CLI, and to the live rows. `transcript.md` ends with a line that lists each replacement and its count, for example "Known words applied: Convio to Konvio (3), Yuri to Jyri (1)." So the form that Whisper wrote stays visible. The user decides if `transcript.md` should change at all (question 1).

The risks, and the rule that answers each one:

| Risk | Example | Answer |
|---|---|---|
| A real word replaced | "Compass" in a sentence about a real compass | Real-word forms stay question lines (rule 5) |
| A form inside a longer word | "Ida" inside "Idaho" | Whole tokens only (rule 2) |
| A broken hyphenated name | "acme-opsdocks" | Hyphens belong to the token (rule 2) |
| Case | "CONVIO", "convio" | The match ignores case, and the output uses the list's spelling (rule 3) |
| Chains | "A" to "B", then "B" to "C" | One pass, no second look (rule 4) |
| Finnish and English in one list | "Yuri" to "Jyri" in an English sentence | One list. Names cross languages, so entries have no language |

## The summary prompt

**Proposal.**

1. Add a "Known words" block to `SummaryPrompt.make`, one line for each entry: the right form, its kind from the heading, and the entry's note. Draft instruction: "The transcript comes from speech recognition. It often spells names and product terms wrong, and one term can appear in several spellings. When a word or phrase sounds like a known word below and fits the context, write the known word. Do not add a known word that the transcript does not support."
2. Ask for a review block at the end of the reply: a fenced code block with the info string `ku-ka-review` and a JSON array of at most 10 items. Each item has `heard` (the exact text from the transcript), `suggestion` (a known word, a best guess, or null), `kind` (person, company, product, term, or other), `quote` (the transcript sentence), and `reason` (a few words).
3. Ku-Ka removes the block from the summary before it writes `summary.md`. It keeps an item only when `heard` and `quote` both occur in the transcript, and drops items that the user already answered. A missing or broken block means no questions. It is never a summary failure.
4. Ku-Ka writes the valid items to `review.json` in the meeting folder, atomically and before `summary.md`, because `summary.md` marks the meeting done. The stage rule ignores the new file (code fact 7). A crash between the two writes runs the summarize step again, which writes `review.json` again.
5. The list adds little to the prompt. 300 entries of about 60 characters are 18 KB, against `ARG_MAX` of 1 MB.
6. Every meeting would send the whole list to `agy` or `claude`, also names from other projects. The user decides if that is acceptable (question 2). Groups of words for each project are a later option.

**Open.** How often `agy` and `claude` return a valid block, and how often the block changes the Markdown sections. If the block breaks summaries, move the suspects to a second CLI call. That doubles the CLI time.

### A separate small fix for owners and the "Me" label

**Proposal.** Change the owner rule at `KuKa/MeetingSummarizer.swift:136` to: "The owner is the name of the person who takes the task, when the transcript says it. Otherwise write Unclear. Never write Me or Them as an owner, because several people can speak under each label." Change the legend at `:126-128` and at `KuKa/Transcript.swift:58` to say that "Me" is the microphone of the Mac that recorded the meeting and that several people in that room can speak on it. `contentForSummary` must keep the old legend as a second boundary, or older transcripts would send their header to the CLI (code fact 5). This fix does not depend on the known-words list and can ship first. A separate research note on speaker labels, [2026-10-28-speaker-labels.md](2026-10-28-speaker-labels.md), was in progress at the same time. If Ku-Ka gets more than two speaker labels, the owner rule and the legend change with them, so the two pieces of work need one decision.

The filler lines "I I I" belong to the silence filter in `WhisperKitTranscriber.trackTranscript`, not to this feature. **Open.** A lone "I" can be real speech, so a rule needs measured examples first.

## Asking and learning

### When Ku-Ka asks

| | Notification when the notes are ready | Review window | Menu item | Live drawer during the meeting |
|---|---|---|---|---|
| Reaches the user | Yes, once | When opened | When the menu opens | During the meeting |
| Room for a sentence and choices | No | Yes | No | Little |
| Text it checks | Whisper's final text | Whisper's final text | Whisper's final text | Apple's draft text, with different mistakes |
| Cost to the meeting | None | None | None | Takes attention, and the drawer can be in a shared screen |

**Proposal.** No questions during the meeting. When the notes are ready and `review.json` has items, the notification says "Meeting Notes Ready" with "3 words to check" in the body, and a click opens the review window. The window has an **Open Summary** button. With no items, a click opens the summary as today. The Meeting Notes menu shows **Check Words (3)…** until the user answers or closes every item. Nothing expires. The window shows at most 5 items per meeting: items whose suggestion is a known word first, then names, then the rest.

### What the review window shows

**Proposal.** For each item:

- The meeting title, the time, and the speaker label of the line.
- The transcript sentence, with the heard form in bold.
- Buttons for the CLI's suggestion and up to two known words that are close in spelling, plus a field for the right word.
- **It is correct as heard** and **Skip**.
- After a choice of a right word, a checkbox **Fix this without asking next time**. It is on by default, and off when the heard form is a real word (rule 5).

One heard form gets one item, also when it occurs in many sentences.

### How answers become entries

**Proposal.**

- A right word adds the heard form to that word's line, or starts a new line under the kind's heading. The checkbox decides ✓.
- **It is correct as heard** adds the word to the "Correct as heard" section. Ku-Ka never asks about it again, and the summary prompt lists it as a known word, so the CLI does not "correct" it.
- **Skip** stores nothing.
- The CLI never writes to the list. Only answers and the user's own edits change it, the same rule as in the user's skill.
- **Update Notes** in the window applies the answers to this meeting. Under the folder lock, Ku-Ka writes `transcript.md` again with the corrector and runs the summary again with the new list. If the CLI fails, the old `summary.md` stays. The user decides if this runs by itself, on a button, or never (question 3).

### Playing back the sentence

**Fact.** The audio goes to the Trash at the start of the summarize step (code fact 3), and `AGENTS.md:18` states the rule that the audio goes to the Trash once the transcript exists. The review items come from the summary step, after that point.

Options:

1. No playback in the first version. **Proposal.**
2. Keep the audio until the review is done or for a fixed number of days. This changes the user's privacy rule.
3. Cut a few seconds around each suspect word into the meeting folder in the transcribe step, then trash the rest. This needs a suspect source before the summary, such as Whisper token probabilities, and also changes the rule.
4. Play from the Trash. The user can empty it, and Ku-Ka does not keep the Trash path today, so this is fragile.

### How the list grows without noise

**Proposal.**

- Entries come only from answers and edits.
- At most 5 questions per meeting, and never one already answered.
- "Correct as heard" stops repeat questions about right words.
- Ku-Ka keeps counts and the last date each entry fired in a small JSON file in Application Support, not in the Markdown, so the user's file does not change after every meeting. A later list window can show entries that never fire.

## Where the list lives

| | `<meetings folder>/known-words.md` | `~/Library/Application Support/Ku-Ka/known-words.json` |
|---|---|---|
| The user can edit it | Yes, in any text editor | Hard |
| Other tools can read it | Yes, next to the meetings | Hidden |
| Parse safety | Hand edits can break a line | Strict |
| Sync | Not synced by default (`~/Meetings`) | Not synced |

**Proposal.** `known-words.md` in the meetings folder. The meeting listing ignores it (code fact 7). An example with invented content:

```markdown
# Known words

Ku-Ka fixes the forms before the arrow in every transcript when the line ends with ✓.
A line without ✓ makes Ku-Ka ask. You can edit this file in any text editor.

## People
- Ravinder / Rabindra / Ravi Indra → **Ravindra** ✓
- Yuri → **Jyri** ✓
- my key → **Maikki**
- **Iida**

## Companies
- Convio / Konvia / Gonvio / Kon Vio → **Konvio** ✓
- Convoy / Conveyor → **Konvio**
- Compass → **Kompassi** (a Finnish company)

## Terms
- acme-opsdocks → **acme-ops-docs** ✓
- Vigmo → **Figma** ✓
- arrow states / erostages → **error states**

## Correct as heard
- Aino
```

In this example, "Convoy", "Conveyor", "Compass", "my key", and "arrow states" are real words, so their lines have no ✓ and make Ku-Ka ask. "Iida" is a known word with no misheard forms. "Aino" is a name that Ku-Ka flagged once and the user confirmed as right.

Format rules:

- One entry per bullet. The heading gives the kind. Heard forms are split on " / ". The right form is in bold. A line with only a bold word is a known word with no variants. Text in parentheses is the entry's note for the summary prompt.
- A line that Ku-Ka cannot read stays as it is, and the menu names the line number. Ku-Ka never deletes a line that it cannot read.
- Ku-Ka reads the file at each use, as it reads `meetingsFolder` today.

Writing safely:

- Ku-Ka writes only after an answer. It takes a `FileLock` on `<meetings folder>/.known-words.lock`, reads the file again, changes one line, and writes the whole file with `.atomic`, as `MeetingFolder.write` does.
- **Fact.** `FileLock` stops only other Ku-Ka processes. A text editor that has the file open can still save over Ku-Ka's change. **Proposal.** Accept this. Ku-Ka re-reads right before each write, so the window is one answer wide.

**Open.** One list or two. The user's other tool keeps its own map. Ku-Ka's list could be the only list, the other tool could read Ku-Ka's list, or the two could stay apart (question 5).

## The live view

**Proposal.** Ku-Ka applies the confirmed forms to the live rows when it builds `LivePreview`. It is a pure function, so `LiveTranscript` stays as it is. No questions in the drawer. Apple's live engine makes different mistakes than Whisper, so forms learned from Whisper's text will miss some of Apple's. `DictationTranscriber` with contextual strings could bias the live engine, but it replaces the engine that the user chose on 2026-10-27, so it needs the measurement first.

## Recommendation

### First version

1. `KnownWords`: parse and write `known-words.md`. Pure text in, text out.
2. `Corrector`: the fixed replacement with the rules above. Pure.
3. The transcribe step runs the corrector on the merged lines and adds the "Known words applied" line. The live preview runs it on its rows.
4. `SummaryPrompt.make` gets the known-words block and the request for the review block. Ku-Ka removes, checks, and stores the block as `review.json`.
5. The review window, the notification text, the **Check Words** menu item, answers that write the list, and **Update Notes**.
6. Ship first, separately: the owner rule and the "Me" legend.

Not in the first version: a Whisper prompt, Apple contextual strings, a change to the audio rule, and word scores.

Seams for test-driven development: `Corrector`, the `KnownWords` parser and writer, the review-block parser and its check against the transcript, the step from an answer to a list edit, `SummaryPrompt.make`, and `MeetingProcessor` with the existing fake summarizer.

### Later, in order

1. Word scores from Whisper token probabilities as a local source of suspects, if the measurement shows that misheard names score low. It needs no alignment pass.
2. A short Whisper prompt with the most-used names, only if the measurement shows better names, no leak, and no cut windows.
3. Audio clips for playback, if the user changes the audio rule.
4. `DictationTranscriber` with contextual strings for the live text.
5. A Finnish suffix rule for names.
6. Groups of known words for each project.

## Measurement plan, not run

Nothing in this plan ran. Ku-Ka was transcribing a real meeting on the Neural Engine, and another agent was timing a model.

What it needs:

- A quiet Mac. Ku-Ka must not transcribe, and no other model work may run, because both use the Neural Engine.
- The Whisper model that Ku-Ka already installed. **Fact.** `~/Library/Application Support/Ku-Ka/whisper-models/large-v3-v20240930_turbo/` exists. Nothing is downloaded.
- For Apple, the installed en-US `SpeechTranscriber` model. **Open.** Whether the en-US `DictationTranscriber` asset is installed. The probe checks `DictationTranscriber.installedLocales` and skips that arm if it is not, because the plan downloads nothing.
- `say` voices. **Fact.** `say -v '?'` lists Samantha (en_US), Daniel (en_GB), and the Finnish voices Eddy, Flo, Reed, and Rocko (fi_FI).
- A throwaway Release-build probe in the scratch folder, not Ku-Ka code, as in the earlier research note. It uses Ku-Ka's decoding options and VAD path.

The script:

- About 10 minutes on two tracks, in the shape of the earlier probe's meeting.
- 20 invented terms in the kinds of the error list: coined company names, names that are close to English words, Finnish first names inside English sentences (a Finnish voice says the name), hyphenated repository names, and product names with an English look-alike. Each term occurs 3 to 5 times.
- 20 control sentences without any term.
- Silences of 10, 30, and 60 s on each track, for the leak test.
- A manifest with the speaker, the times, and the text of each line, as the reference.

The arms, each run 3 times, because a temperature fallback can sample:

1. Whisper with no prompt.
2. Whisper with a comma list of the terms, at about 20, 50, and 100 tokens.
3. Whisper with one transcript-style sentence of the terms, at the same sizes.
4. Apple `SpeechTranscriber` with `.transcription`, with and without contextual strings. Apple's forum answer predicts no change.
5. Apple `DictationTranscriber`, with and without contextual strings, at most 100 phrases, if the asset is installed.
6. The corrector and the summary CLI on the transcripts from arm 1: `agy` and `claude`, each with and without the known-words block.

The scores:

- Term recall: the share of spoken terms with the exact right spelling.
- Leaks: list terms in the output where the script has none, counted apart for silence and for speech.
- The word error rate on the other words, for the study's finding.
- Windows that reach the 223-token limit, and the words lost after them.
- Temperature fallbacks (`timings.totalDecodingFallbacks`) and segments with a compression ratio above 2.4.
- The word score of misheard term words against other words, to choose a threshold for the later suspect source.
- For the CLIs: summaries with every term right, valid review blocks, the share of review items that are real mistakes, and the share of real mistakes that become review items.
- The token count of each prompt, from the WhisperKit tokenizer.

Generated speech is cleaner than a real meeting, so the scores are an upper limit. `RealMeetingAudioTests` can run a prompt on real audio later, but only on a meeting that the user chooses.

## Questions only the user can answer

1. Should Ku-Ka change `transcript.md` with confirmed fixes and list them at the end, or keep `transcript.md` as Whisper wrote it and fix only the text for the summary?
2. Can the whole list go to `agy` or `claude` with every meeting, also names from other projects? Or do you want groups for each project?
3. Should an answer update the current meeting's notes by itself (one more CLI run), only when you click **Update Notes**, or only help later meetings?
4. Do you want to hear the suspect sentence? That needs a change to the rule that the audio goes to the Trash once the transcript exists. The options are to keep the audio until the review, to keep short clips, or no playback.
5. Should the list live in the meetings folder, where you can edit it, or in Application Support? Should Ku-Ka and your other tool use one list?
6. How should Ku-Ka ask? A notification click that opens the review window, a menu item only, or both? How many questions per meeting at most?
7. What prompt did you try when "a prompt leaked into the text"? Its text, its form, and its length would show if a names-only prompt is worth a measurement. This research could not read the log of that session.
8. Is "Unclear" right as the owner when the transcript does not say who takes a task?

## How this note was made

- The agent read Ku-Ka at `e0d5365`, the pinned WhisperKit checkout, the macOS 27 Speech SDK interface, and the decoder metadata of the installed model, without a model load.
- Web sources: Apple's documentation pages through their JSON form, two Apple forum threads, the OpenAI cookbook and speech-to-text guide, the `openai/whisper` source, and two arXiv papers.
- One command printed the option sets of Apple's five presets. One command listed the installed `say` voices. Neither used audio.
- The agent read no meeting folder, transcript, or summary. The error patterns came from the main session, with the names changed. The agent did not read the log of the earlier Whisper session.
