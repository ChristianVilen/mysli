# Spoken dictation formatting

Say "new line" for one line break and "new paragraph" for two. Common punctuation
phrases become punctuation. This applies locally, so Claude failure keeps the
formatting. The change stays on the dictation branch. TDD is approved where useful.

## Approach

Use a local phrase converter before prose cleanup. Claude receives the converted
text and must keep its line breaks. Its result is checked one line at a time.
Claude-only conversion would lose formatting on failure, so local conversion is
the proposed approach accepted for implementation.

Preparation classifies text once as final or prose. Context preparation turns
prose into a polish request; final text goes straight to delivery. Neither context
preparation nor the polisher classifies edited text again. The heard text stays
in `LastDictation`, outside the polish request. Prose filler removal and formatting
use one quote reader. Shell quoting keeps its own rules.

Support comma, period, full stop, question mark, exclamation mark, exclamation
point, colon, and semicolon. Match whole phrases without case sensitivity and
allow punctuation added by Whisper after a phrase. Quoted phrases stay literal.
Recognized shell commands keep their existing text behavior.

Keep empty lines and leading or trailing requested breaks, including a dictation
that only says "new line". Paste still uses Command-V and restores the clipboard.
A line break in pasted text can submit input in a terminal. Document this change.
Do not add editing actions, key events, preferences, or dependencies.

## Checks

Test local conversion, quoted phrases, shell text, Unicode/control handling,
Claude line preservation and rejection, formatted Claude input, and one paste
transaction. Use fakes and injected time. Real speech and app paste remain manual.
