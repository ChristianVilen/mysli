# Meeting panel cleanup

Issue [#55](https://github.com/ChristianVilen/ku-ka/issues/55) brings manual notes and the live transcript into one floating panel. This page records the interface choices from the mock review. The [implementation plan](../plans/2026-11-03-meeting-panel-cleanup.md) defines storage and integration work.

## Chosen interface

The user chose **Read and write**. The expanded panel shows the live transcript above the manual notes. The compact panel keeps the recording timer and controls. Notes expand inside this panel instead of opening another window.

The panel stays resizable. Transcript and notes must remain usable when the available height is small. New speech must not interrupt note editing or text selection.

The notes remain editable after Stop. The live transcript keeps its existing in-memory lifetime. Closing or collapsing the panel must preserve the existing unsaved-draft protections.

## Native materials

Use Apple's native Liquid Glass where it helps separate the floating controls from the meeting app. Build on the existing panel's `NSGlassEffectView` support.

Keep the transcript and editor surfaces quiet enough for long text and screenshots. Do not stack glass effects behind individual rows or add a glass frame around each attachment. Use native text, focus, selection, and editing behavior.

Support light and dark appearances, Reduce Transparency, Increase Contrast, and Reduce Motion. Expanding and collapsing the panel must remain responsive to new input.

## Timestamped notes and transcript

Every logical note row gets a timestamp with its first text or screenshot. Empty editor placeholders are not notes yet. A row keeps its timestamp when edited. A visual line wrap does not create another row. Screenshots retain their row's time.

The live transcript and saved note times must correlate with the final transcript. The current recording timer excludes pauses, while audio files include three seconds of silence after each resume. The implementation must account for this difference.

Enter creates a new timestamped row. Shift+Enter adds a line within a row. Notes added after Stop are marked as after the recording rather than assigned an invented speech time. These rules were included in the mock that the user approved for implementation.

## Screenshots

Paste and drag and drop are the only ways to add screenshots. There is no upload button, file picker, or capture button. Attachments stay with their original meeting and appear with the notes.

## Live transcript

Users can select text with the cursor and copy it. Selection must survive incoming updates where the selected text has not changed.

Incoming gray draft text stays below committed messages. A draft must not remain above newer messages from the other audio track.

## Calendar titles and reminders

Keep standard macOS notifications. Persistence belongs to the user's macOS notification settings. Do not build a custom reminder panel.

Calendar-started recordings already save the event title in `meeting.json` and use it for document headings and window titles. The remaining title work must identify where that title is missing before adding another calendar lookup.

## Alternatives and verification

The alternative mock switched between transcript and notes. The user chose the combined view so both remain visible while writing.

The user approved TDD for this issue. Test observable draft order, timestamp mapping across pauses, folder-bound note and attachment saves, and native editing behavior. Use synthetic recording data and temporary meeting folders. Do not request real capture or calendar permissions, load speech models, or replace the installed app for verification.
