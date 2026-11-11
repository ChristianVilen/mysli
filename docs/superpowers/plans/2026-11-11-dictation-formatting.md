# Spoken dictation formatting implementation plan

> Implement in this session with superpowers:executing-plans. Use TDD for behavior.

**Goal:** Convert spoken line breaks and common punctuation before dictation paste.

**Architecture:** A local converter owns the phrase list. DictationText owns prose
cleanup and per-line Claude checks. PasteText carries validated multiline text.

**Tech stack:** Swift, Foundation, AppKit, XCTest. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-11-dictation-formatting-design.md`.

## Constraints and review focus

Keep work on this branch. Do not use real capture, Claude, or paste in tests.
Preserve standalone and trailing breaks. Keep quoted phrases literal. Preserve
shell commands. Reject Claude output that changes line boundaries or text.

## Tasks

- [x] Add failing behavior tests in DictationTextTests and PasteTextTests. Run them.
- [x] Add DictationFormatting.swift with local phrase conversion. Update
  DictationText.local, prose cleanup, and PasteText to preserve requested breaks.
  Run the focused tests until green.
- [x] Add failing Claude line checks and formatted wire-input tests. Update
  DictationText.accept, DictationClaudeWire input/instructions, and the polisher's
  local-only path for formatting without words. Run dictation tests until green.
- [x] Verify multiline delivery with the existing fake clipboard transaction.
  Update README, CONTEXT, and the earlier design's superseded formatting rule.
- [x] Run the full test suite, scripts/check-tests.sh, and git diff --check.
  Review the final diff. Record manual checks as not done.

## Verification

The first focused run failed because spoken phrases stayed as words and paste
text flattened line breaks. Later focused runs covered Claude input, line layout,
formatting without words, and duplicate punctuation from Whisper. All passed.

Code review found quote protection failing on contractions and spelling correction
joining words across requested breaks. New tests failed before each fix and passed
afterward. The reviewer checked both fixes and reported no further findings.

The final full suite passed 1,161 tests with 12 skips and no failures. The duration
check and `git diff --check` passed. Changes remain local on the dictation branch.

These review fixes have not been checked with real microphone capture, speech
recognition, paste in other apps, physical keys, or VoiceOver.

## Approved judo review fixes

- [x] B1: Classify text once in preparation. Carry final text or a prose polish
  request through the controller. Read Claude context only for prose. Delete the
  second classifier and the formatter call used as a yes/no check.
- [x] B2: Share one quote reader between prose filler removal and formatting.
  Delete the formatting expression's quote grammar. Preserve shell quoting.
- [x] C1: Remove `DictationPolishRequest.heardText` and its callers. Keep the heard
  text in `LastDictation`.
- [x] Run full verification and review the fixes.

Regression tests first failed for skipped prose polish, unwanted context reads
for final text, and deleted fillers in quoted contractions. Review also found
apostrophes after digits changing quote boundaries. Its regression test failed
before the word-character rule was corrected. All tests now pass, and review
confirmed B1, B2, and C1 resolved.
