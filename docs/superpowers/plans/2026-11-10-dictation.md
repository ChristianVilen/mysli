# Dictation implementation plan

> Use subagent-driven development. Give each slice to a fresh implementer and review it before the next slice. TDD is approved for this whole build.

**Goal:** Hold a key, speak in English, release, and paste safe polished text at the cursor.

**Architecture:** One main-actor controller owns the active operation through a private state enum. Adapters own key input, capture, speech, Claude, context, and the clipboard transaction. UI reads a presentation value with no dictated text.

**Tech stack:** Swift 5 language mode with Swift 6.2, macOS 26+, AppKit, AVAudioEngine, Carbon, the selected on-device speech engine, and the existing Claude CLI.

**Spec:** `docs/superpowers/specs/2026-11-10-dictation-design.md` is the authority. The user approved its product decisions in the handover on 2026-11-10.

**Status:** Implemented and reviewed on the dictation branch. Functional head `147e047` passed 1,134 tests with 13 opt-in or snapshot skips, the duration check, and a Release build. The user tested dictation in the real app on 2026-11-11. The branch is not merged.

## Global constraints

- Use the existing dictation worktree. Never push, open a PR, merge, or create another worktree.
- Commit small slices on this branch. Never add co-author lines or a generated footer.
- Follow AGENTS.md. No Python. Use apply_patch for edits. All scratch files go in the task's unique temporary directory.
- Normal tests use fake OS boundaries and injected time. No real microphone, paste, Claude, model downloads, or permission prompts. Each normal test takes less than 0.1 seconds.
- Use TDD at the controller seam or the type that owns the rule. Do not duplicate rule tests in integration tests.
- Dictation text, audio, clipboard snapshots, and Claude I/O stay in memory. Do not use the existing disk-based ProcessCommandRunner.
- Dictation uses Haiku through Claude, never Settings.summaryTool. The complete safe CLI arguments and JSON line format are pinned by tests.
- Speech selection and fresh-idle process timing must be measured before pipeline code.
- A hold shorter than 0.3 seconds does nothing. Limit recording to 120 seconds and warn for the last 10 seconds. Claude has 2.5 seconds from stdin write.
- Cancellation invalidates the operation synchronously. No late result can paste. A clipboard restore after Command-V survives cancellation.
- No final newline, no Return, no tools, no instruction execution. Commands remain text.
- Read known words at each use. Send correct spellings only, never notes, dates, or check marks. Nearby context is optional, at most 500 preceding characters, never from a secure field.
- Changes to tool input include a local README privacy change in the same commit. Keep AGENTS.md and README.md edits small because main has unrelated uncommitted changes.

## Review focus

- Release or cancellation while capture startup is pending must stop sample admission immediately.
- Disable during preparation, transcription, or polish must reject late completions and release resources.
- Carbon fallback must cancel with Escape without a second passive monitor or Input Monitoring permission.
- An external copy during paste must win over restoration. Restore must not add clipboard history.
- New onboarding must leave dictation off, including Skip. Refresh and launch must never write preferences or ask for permission.

## Architecture decision

Two independent read-only candidates and a judge preferred an async main-actor controller over a reducer with an effect interpreter. Use a private state that carries its owned operation. Do not keep a second current-hold variable that must match the state. Graft the separate safe-paste transaction and a validated nonempty PasteText value with no final newline.

The controller owns key callback attachment. AppDelegate composes objects. Capture must have a synchronous seal or stop request, even if its result is awaited later. An async finish method alone does not close the race before a pipeline Task starts.

The speech interface must match the measured path. If Apple wins using progressive input, use a recognition session that consumes ordered samples during the hold. Do not substitute buffered post-release inference and claim the streaming measurement. Whisper may buffer behind that same session interface if it is selected.

Whisper passed the measured gate. The reviewed adapter uses `loadSamples(for:)` and `SampleTranscriptionSession.transcribe(samples:)` alongside file transcription. Capture `begin` also takes a typed failure callback so background startup errors reach the owned hold. Conversion finishes on the audio queue before result completion. AppDelegate's single `whisperTranscriber` value serves meetings and dictation.

Control+Option+D is the builder's default Carbon choice. A real CopySymbolicHotKeys lookup found no enabled conflict on this Mac. Real Carbon registration and release returned success for this combination and for unmodified Escape. The existing registrar owns a temporary Escape registration while an operation can be cancelled.

## Task 1: Controller and states

Own `DictationController.swift`, `DictationDomain.swift`, and controller tests. Define the small adapter contracts needed by later slices. No OS adapters in this task. Use private owned operation states and a presentation projection with no text. Keep the most recent dictation with text as heard and as selected for paste in memory, before attempting delivery, so paste failure still permits replay.

- [x] Write failing controller tests with fake keys, capture, speech, polish, clipboard, keystrokes, and clock.
- [x] Prove press/release, duplicate input, 0.299-second cancellation, the 0.3-second boundary, Escape/chord cancellation, the 110-second warning, and the 120-second stop.
- [x] Prove silence skips Claude and paste, polish failure uses local text, late results after cancel/disable do not paste, and preparation completion after disable stays disabled.
- [x] Prove release seals pending startup before any async work. Prove replay cannot overlap a live operation or clipboard cleanup and uses no new Claude request.
- [x] Implement only the controller and fakeable contracts. Run focused tests, inspect the diff, and commit. Record the final signatures for the next implementer.

## Task 2: Key input

Own `DictationKeyInput.swift` and edits to CarbonHotkeyAPI, HotkeyRegistration, HotkeyManager, HotkeyShortcut, and their tests. Add only the short Fn exception to AGENTS.md, with "decided by the user, 2026-11-10".

- [x] Write failing tests around real registrar policy with fake Carbon calls and a fake Fn event source.
- [x] Add Carbon release delivery for dictation. Existing actions remain press-only. Give dictation and temporary Escape their own gates.
- [x] Add exactly one passive Fn monitor. Observe the Fn flag and key-down cancellation only. Never block or change events, record key text, or poll Secure Input.
- [x] Prove Fn repeats, second key, Escape, re-enable, disable, stale delivery, registrar failure, and temporary Escape cleanup. No extra monitor in Carbon mode.
- [x] Permission requests belong to explicit enable/setup. Expose read-only availability at launch. Run focused tests and commit.

## Task 3: Microphone and speech samples

Own `DictationMicrophone.swift`, the selected speech adapter and its sample entry point, and focused tests. Preserve meeting file transcription. Only the existing permitted file imports WhisperKit. If Whisper wins, one shared model owner serves dictation and meetings and keeps a retention lease while dictation is on.

- [x] Write failing tests for in-memory sample conversion, bounded audio, synchronous seal/cancel, pending startup, and the speech-session contract selected by measurement.
- [x] Add AVAudioEngine capture with Microphone permission only. No audio file, ScreenCaptureKit, or Screen Recording gate.
- [x] Add a narrow samples session alongside TranscriptionSession without breaking file callers. No known-words Whisper prompt. Use a separate dictation no-speech policy with audio evidence.
- [x] Prove silence and valid short speech, empty samples, cancellation, sample rate/channel conversion, and preservation of meeting semantics. If sharing Whisper, prove one load during concurrent acquisition and no unload while leased.
- [x] Run focused tests, reconcile interfaces, and commit.

## Task 4: Claude polish

Own `DictationPolisher.swift`, `DictationClaudeProcess.swift`, `DictationText.swift`, tests, the opt-in Real Haiku safety check, and a small README privacy addition.

- [x] Start with failing tests that pin the full CLI argument list, stream JSON line, result parsing, 2.5-second deadline from write, and failure fallback.
- [x] Keep one fresh ready process for each dictation in an empty folder. Use pipes and bounded memory for stdin/stdout/stderr. Retire after one result and prepare its successor in the background.
- [x] The timeout must settle the request without waiting for a cancelled child to exit. Parse error results, EOF, startup failure, and stale results as unavailable. Keep process cleanup separate from paste eligibility.
- [x] Add data-only prompt blocks, local confirmed corrections and simple cleanup, command protection, no-final-newline construction, and an output guard. Pin thresholds with passing normal cleanup and rejected instruction-like output.
- [x] Add opt-in hard cases for commands, questions, instruction injection, and instructions in nearby context. Never run real Claude in normal tests.
- [x] Run focused tests and the authorized real synthetic safety check once. Record exact outputs and failures. Commit code and its privacy description together.

## Task 5: Context

Own `DictationContext.swift`, context and prompt-input tests, and a small README privacy adjustment if the implemented input changes.

- [x] Write failing boundary tests for app name, optional 500-character prefix, failed reads, secure fields, malformed ranges, and Unicode boundaries.
- [x] Read Accessibility only. Reject secure fields before any value read. Read no selected text after the cursor and no more preceding text than needed.
- [x] Read KnownWordsFile at each use. Map words and correct-as-heard entries to spellings only. Use KnownWordsList.corrector locally and keep list metadata out of the prompt.
- [x] Run focused tests and commit.

## Task 6: Paste

Own `DictationPasteboard.swift`, safe-paste tests, and a small history count-adoption seam in ClipboardHistoryController.

- [x] Write failing tests with fake clipboard representations, existing KeystrokeSending, and injected time.
- [x] Snapshot every item and advertised representation before a write. Refuse an incomplete or raced snapshot. Write text and org.nspasteboard.TransientType together.
- [x] Send only the existing Command-V. Restore only if the transient write still owns the clipboard. A new external copy wins. Adopt the exact returned restore count synchronously so history skips it.
- [x] Prove empty clipboard, several items and formats, cancellation before and after key send, external copy, restore failure, and serialization with replay. Keep data only in memory.
- [x] Run focused tests and commit.

## Task 7: UI, Settings, menu, and permissions

Own `DictationPanel.swift`, its menu section, and the small integration edits in AppDelegate, Settings, MysliTool, onboarding, Settings views/controllers, StatusMenu, RequiredPermissions, Info.plist, and related tests. Use frontend-pr and native UI verification guidance but obey the user's no-PR instruction.

- [x] Start with failing integration tests for enable/disable wiring, dictation off by default even on onboarding Skip, saved preference contracts, and no writes or permission prompts on launch/refresh.
- [x] Add the wordless mouse-ignoring nonactivating FloatingPanel. Match the meeting panel's native glass, corners, type, and meter. Place it bottom-centre on the focused window's screen. Respect reduced transparency and motion.
- [x] Show listening, polishing, unpolished, and error by meter/progress/shape. Terminal states last two extra seconds through injected time. Add a distinct top-left listening mark without losing other marks.
- [x] Add the tool, menu replay action, Settings switch, Fn/Carbon choice, nearby-text switch, explicit permission setup, and Keyboard Settings guidance. RequiredPermissions lists Microphone and Accessibility for dictation and the Fn adapter's extra permission only when relevant. Never change macOS preferences.
- [x] Update microphone wording, README use/privacy/permissions, short AGENTS instruction/data rules, and CONTEXT terms. Keep AGENTS under 150 lines and README edits local.
- [x] Run focused tests and inspect deterministic native renders. Commit.

## Finish

- [x] Run the full test suite and scripts/check-tests.sh against its result. Run a Release build.
- [x] Review the whole branch independently, including memory-only I/O, no tools, command preservation, cancellation, and preference side effects. Fix accepted findings and recheck the affected paths.
- [x] Add measurement and verification results to the spec. Keep manual checks that nobody did separate from test results.
- [x] Remove this task's temporary files after all children and commands stop. Report working behavior, numbers, manual checks not done, open issues, and builder choices.
