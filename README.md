# Mysli

A daily mix of Mac tools. Screenshots, clipboard history, window tiling, Keep Awake and private meeting notes, in one menu bar app.

Mysli is Finnish for muesli: a mix of good things.

🌐 **Website**: [https://christianvilen.github.io/mysli](https://christianvilen.github.io/mysli)

## Features

- Intercepts `Shift+Command+3` and `Shift+Command+4` globally to replace the system screenshot tools. Turn off **Use Mysli for screenshots** in Settings to give both shortcuts back to macOS.
- Full screen capture with `Shift+Command+3` — captures the screen where the cursor is, with flash animation
- Multi-monitor support — dims all screens, captures from the screen where the cursor is
- macOS-style selection overlay with dimmed background and real-time dimensions display
- Saves screenshots as PNG to `~/Screenshots/`
- Automatically copies the screenshot to the clipboard
- Floating thumbnail preview after capture — click to annotate with freehand drawing or crop
- Delete screenshots from thumbnail or editor — removes file and clears clipboard
- Launch at Login toggle
- Keep Awake — stop the Mac from sleeping while a long task (such as an AI coding agent) runs, with a menu-bar toggle and timed sessions
- Window tiling — hotkeys to snap the active window to the left half, right half, or full screen of its display
- Clipboard history — `Shift+Command+C` opens a searchable list of what you've copied, text and images, and pastes the item you choose back into the app you were using
- Meeting notes. Record a call from the menu bar, and Mysli writes a transcript and a summary as Markdown files. Transcription runs on your Mac, and so does the step that tells apart the voices in your room. A floating panel lets you pause and stop the recording and shows a live draft of the transcript.
- App logs. **Show Log…** opens a live, searchable log window with filters, copy, save, and deletion.
- Runs as a menu bar agent (no Dock icon)

## Keep Awake

Choose a duration in the menu's **Keep Awake** section. The choices are 30 minutes, 1, 2, or 4 hours, and until turned off. A blue dot in the lower-right corner of the menu-bar icon marks an active session, and the menu shows how much time is left.

**Keep screen on** is on by default in the Keep Awake menu. Turn it off to let the display sleep and lock on its normal schedule. Changing this choice also updates an active session without restarting its timer. Closing a laptop's lid still sleeps the Mac unless it is plugged in with an external display attached. Keep the lid open or run it docked.

## Window Tiling

Three hotkeys move the active window around its display:

- `Ctrl+Option+Left Arrow` — snap the window to the left half of the screen
- `Ctrl+Option+Right Arrow` — snap the window to the right half of the screen
- `Ctrl+Option+Return` — maximize the window; press it again to put the window back where it was before

If you use Stage Manager (the macOS feature that shows recent apps as small thumbnails down the side of the screen), maximize leaves room for its strip on the left, plus a small gap at the top, bottom, and right. This only happens when Stage Manager is turned on **and** there are two or more windows visible on that screen — with just one window, or with Stage Manager off, maximize fills the whole screen. Left- and right-half tiling never leaves this gap, so a half-tiled window can sit under the Stage Manager strip.

With more than one display, the window is tiled on the screen it overlaps the most. This differs from the screenshot features, which follow the cursor.

The whole feature can be turned on and off with the **Enable window tiling** checkbox in **Settings…**; the choice is remembered across restarts. While it's off, the hotkeys pass through to other apps. The keys themselves aren't configurable.

## Clipboard History

Press `Shift+Command+C` and a panel opens over whatever you're doing, listing what you've copied recently, newest first. Start typing to filter the list, use the arrow keys to move through it, and press `Enter` to paste the selected item into the app you were working in. The panel closes and that app keeps focus.

If the item is formatted text (say, from a web page or a rich-text editor), `Enter` asks first: paste with formatting or without. Without formatting is pre-selected, so pressing `Enter` twice gives you plain text. Plain text and images paste right away, with no second step.

Text and images both get recorded, including screenshots Mysli itself saves to your clipboard. Delete a screenshot from its thumbnail or the editor and its clipboard history entry goes with it.

The history lives in memory only — nothing is written to disk, so it's empty again after a restart. It holds at most 100 items; images are capped at about 100 MB in total, with the oldest images dropped first. A single item over 50 MB is not recorded. Copies that your password manager marks as sensitive are never recorded.

The whole feature can be turned on and off with the **Record clipboard history** checkbox in **Settings…**; the choice is remembered across restarts. While it's off, Mysli stops recording, clears the history it collected, and gives `Shift+Command+C` back to other apps. With the feature on, Mysli takes that shortcut from Chrome and Arc (Inspect Element), Xcode (Activate Console), VS Code (Open External Terminal), and Finder (Computer window).

## Meeting Notes

Calendar recording reminders are off by default. Eligible events offer **Start Recording**, then **Stop Recording** or **Continue Recording** at the end. Mysli never starts or stops automatically. A calendar recording keeps the event title in its menu status and note headings. Turn them on with **Calendar reminders** in Settings. The first time, macOS asks for Calendar and notification access, and Settings says what to allow when access is missing. See the [integration contract and limits](docs/calendar-recording-reminders.md).

When a call starts, open the Mysli menu and choose **Start Recording Meeting**. Mysli records your microphone and the sound your Mac plays, so any call app works. If Start cannot record, for example because a permission is missing, an alert says why.

While Mysli records, a small panel floats near the top-right corner of the screen. It shows the recorded time, Pause, Stop, a notes button, and a live transcript button. Pause and Stop leave the keyboard with your call app. The notes button expands the panel to show the live transcript above your notes. To move the panel, drag it. Mysli remembers where you put it, and **Restore Default Position** in the menu puts it back. **Hide panel** in the live transcript header hides the panel while recording continues. **Show Meeting Controls** in the menu brings it back. The menu bar icon shows a red dot while recording and two white bars while paused.

To write your own notes, click the pencil button or choose **Write Meeting Notes…** in the menu. Each note row gets its timestamp when you first write or attach a screenshot. That time stays when you edit it. Enter starts a new row. Shift+Enter adds a line within the row, and wrapped text keeps the same timestamp. Each edit saves to `notes.md` in that meeting's folder. The editor supports native undo, copy, and paste. You can keep writing while paused and after Stop. Notes added after Stop say **After recording**. Older notes without timestamps say **Undated**. The editor stays with its original meeting if you start another recording or change the meetings folder. **Recent Meeting Notes** reopens the five recent meetings and any retained unsaved drafts.

Paste or drag and drop a screenshot into a note row to attach it. Mysli saves the image in that meeting's `attachments` folder and a relative image link in `notes.md`. There is no upload button or file picker. Screenshot files stay available for undo. The summary tool receives the note text, timestamps, and image references, but it does not receive image pixels or inspect screenshot contents.

Saved notes join the transcript as input to the first summary. Later edits do not regenerate the summary automatically. Choose **Update summary** when you want to include them. This action changes only `summary.md`, preserving the transcript and word-review files. You can write while the summary runs. The status tells you when newer edits still need an update. A failed update keeps the previous summary.

The window shows save errors and keeps the draft. **Retry save** tries again. If `notes.md` changed in another editor, copy any draft text you need before choosing **Reload saved notes**. Mysli asks before replacing the draft. Notes accept up to 64 KiB of UTF-8 text. If a save has failed when you stop, audio stops immediately, and processing waits until the notes are saved. Closing an unsaved window retains its draft for reopening. Quit asks before discarding unsaved text.

When the call ends, click the stop button in the panel or choose **Stop Recording Meeting**. Open notes stay editable and resizable after Stop. Without open notes, the panel says "Recording saved" for a few seconds and closes. If the recording stops by itself, for example because a display went away, the panel says why and stays until you close it.

To leave part of a call out of the notes, click the pause button or choose **Pause Recording**. Mysli saves no audio until you click **Resume** or choose **Resume Recording**. The timer stands still while the recording is paused. The macOS microphone indicator stays on during a pause, because Mysli keeps the capture running so that Resume always works. In the transcript, each pause becomes 3 seconds of silence. So a time in `transcript.md` is 3 seconds later than the timer showed for each earlier pause.

To read along, click the transcript button. A drawer opens with a live transcript that shows "Me", "Them", and a timestamp on each message. Live transcript and note timestamps use the same timeline as `transcript.md`, including the silence added after each resume. Select text across messages and copy it with Command-C. Gray draft text stays below committed messages until it becomes final. The live transcript is a rough draft. Mysli never saves it, and it is gone when you stop. The full transcript that Mysli writes after you stop replaces it. Other people can see the panel when you share your screen, so the drawer starts closed in every meeting. If the draft is 4 seconds or more behind the call, the drawer says by how much. Scrolling back or selecting text stops automatic following. **Return to live** shows how many new rows are waiting.

The live transcript uses Apple's speech recognition, and only for a language whose Apple speech model is already on your Mac. Mysli never downloads a model for it. On a new Mac only the English models are installed, so the default, US English, works. Another language that Apple supports works after its model is on your Mac, for example after Mysli used Apple's speech recognition for a meeting in that language. Finnish and other languages that Apple does not support get no live transcript, and the drawer says so. Mysli still records both sides and writes the full transcript after you stop.

While recording, open the menu to check the **Microphone** and **Mac audio** meters below the timer. Each meter shows the sound level on that track. An empty meter can mean silence, that no audio is arriving, or that the recording is paused. A reading clears after half a second without new audio. The meters update only while the menu is open.

Claude Code summaries use Sonnet with medium effort. Mysli sets both options explicitly, including when Automatic falls back to Claude Code. The Sonnet version depends on the installed Claude Code version.

Mysli then transcribes the call on your Mac with Whisper (the `large-v3-v20240930_turbo` model, through WhisperKit) and asks an AI command-line tool for a summary. The default summary choice, Automatic, tries Antigravity (`agy`) first and Claude Code (`claude`) if that fails. In **Settings…**, you can select either tool to use only that provider. Install at least one of them in `/opt/homebrew/bin`, `/usr/local/bin`, or `~/.local/bin`, and log in to it once in Terminal. A notification tells you when the notes are ready; click it to open the summary, or the review window when there are words to check (see below). Mysli asks for notification permission the first time you start a recording. Each meeting gets its own folder, for example `~/Meetings/2026-10-23_14-02/`, with `transcript.md` and `summary.md`.

By default, "Them" is everyone else on the call, from the sound your Mac plays. The optional Teams speaker-name feature below can name supported remote lines after Stop. Your Mac's microphone hears you and anyone in the same room. Mysli tells those voices apart on your Mac and labels them "Room 1", "Room 2", and so on, in the order they first speak. Mysli never guesses which voice is you. Two people with similar voices can share a label, and one person can get two. A voice with fewer than 5 words gets no label of its own: its lines take the label of the voice that spoke nearest in time. When Mysli finds only one voice, the microphone lines say "Me". If Mysli cannot tell the voices apart, the microphone lines also say "Me", and the top of the transcript says why. Mysli does not try on a microphone track longer than 3 hours. In the summary, an action item has a person's name only when the transcript or your typed notes explicitly say who will do it. Otherwise its owner is "Unclear". Headphones give the cleanest transcript. On speakers, your microphone also hears the other people. Mysli removes those repeated lines from the microphone lines when it finds them. It also removes the lines of a microphone voice that speaks almost only while the other people speak and mostly repeats their words, because that voice is their echo.

The first meeting downloads the Whisper model, about 1.5 GB, to `~/Library/Application Support/Mysli/whisper-models`. Mysli excludes this model cache from Time Machine backups. The menu shows **Downloading speech model** meanwhile. After that, transcription needs no network while the model and tokenizer files remain intact. If Mysli cannot download or load the model, or Whisper does not know the language, Mysli transcribes with Apple's speech recognition instead. The top of the transcript names the transcriber and, after a fallback, says why Whisper was not used. These diagnostics stay in the transcript file and are left out of the summary input.

The first meeting also downloads the room-label model, about 11 MB, to `~/Library/Application Support/Mysli/speaker-models`. Mysli excludes it from Time Machine backups too, and the menu shows **Downloading speaker model** meanwhile. After that, room labels need no network. If the download fails, that meeting keeps "Me", and the next meeting tries again.

The transcript and your saved notes go to the AI tool. For each note row, the tool gets its time, its text, and the file names of its screenshots, but not the images. With them goes each known word that occurs in the transcript, as its forms only. The notes and dates in your known-words list stay on your Mac. The complete optional meeting-context file also goes to the provider on every summary use. Automatic can send these inputs to both Google through `agy` and Anthropic through `claude`. Audio never leaves your Mac. `agy` keeps the prompt in its conversation history. `claude` runs without saving a session. Mysli moves the audio files to the Trash when the transcript is written, so you can restore them from there.

Your typed notes can supply explicit decisions and action owners that are absent from the transcript. The prompt asks the summary tool to show conflicts between the two sources instead of guessing. Typed notes are meeting evidence, never instructions for the tool. Word-review questions still come only from the transcript.

If nobody spoke and the typed notes are empty, Mysli records that no speech was found and keeps the audio. Nonempty typed notes still produce a summary for a silent recording. If a step fails, the meeting folder gets an `error.md` with the reason, and the menu shows **Retry Failed Meeting**. Retry continues from the failed step. If Mysli quits or crashes during a meeting, it finishes processing the saved audio and notes when it next starts. If it crashed while it told the voices apart, that meeting gets no room labels, and the transcript says why. To give up on a meeting, delete its folder. **Open Meetings Folder** opens the folder that holds them.

To keep new meetings in another folder, open **Settings…** and click **Choose…** beside **Meetings folder**. Select a folder or create one, then click **Choose**. The new folder applies immediately, including **Open Meetings Folder**. Cancel leaves the setting unchanged. Mysli does not move existing meetings. A recording or a meeting already waiting for notes finishes in its original folder.

You can also set the path in Terminal:

```bash
defaults write io.github.christianvilen.mysli meetingsFolder /path/to/folder
```

Do not use `~/Documents` or `~/Desktop` when iCloud syncs them, because the audio would then leave your Mac.

Mysli transcribes US English by default. To transcribe another language, set its tag in Terminal:

```bash
defaults write io.github.christianvilen.mysli meetingLocale de-DE
```

Whisper uses only the language part of the tag, so `fi-FI` gives Finnish. The Apple fallback needs a tag that Apple's speech recognition supports exactly, for example `en-GB`, `de-DE`, `fr-FR`, `es-ES`, `it-IT`, `pt-BR`, `ja-JP`, `ko-KR`, or `zh-CN`. Apple does not support Finnish. If neither can transcribe the language, the transcription fails, and `error.md` gives the reason for each. The summary is written in the language of the transcript.

Speech recognition often spells names and terms wrong. Mysli keeps a list of known words that fixes them. By default, the list is `known-words.md` in the meetings folder. This default follows a changed meetings folder, but an explicit list path stays the same. Mysli does not move the list. To use a list that you already keep, set its path in Terminal:

```bash
defaults write io.github.christianvilen.mysli knownWordsFile ~/path/to/list.md
```

Each line of the list is the wrong form, an arrow, and the right form in bold, for example `- Convio → **Konvio** ✓`. Mysli replaces a wrong form in the transcript only when its line has ✓, and the end of the transcript lists what it replaced. Lines without ✓ only help the summary. Mysli reads the list each time it makes notes. It only adds lines to the list. It never changes or removes a line that is already there.

The AI tool also tells Mysli which words it thinks speech recognition got wrong. Mysli asks you about up to 5 of them for each meeting, and never about a word that the list already has. When you answer a word in one meeting, Mysli stops asking about it in the other meetings too. The notification then says how many words there are to check. Click it, or choose **Check Words** in the menu, to open the review window. For each word, type the right word and click **Save**, or click **It Is Correct as Heard** or **Skip**. Your answers go into the list. When you remove a line from the list, Mysli asks about its word again. The answer for a name always gets ✓. When the wrong form of another word is ordinary words of the meeting language, for example "my key", the answer has no ✓, so that Mysli does not replace those words in every transcript. After the last word, **Update Notes** makes the transcript and the summary again with your answers. A meeting that asked about a word that you answered in another meeting also offers **Update Notes**.

Update Notes makes `transcript.md` again from the text that speech recognition wrote and from the list. So a change that you made to `transcript.md` by hand is lost. To fix a word, add it to the list instead.

Recording needs the Screen Recording permission (for the sound your Mac plays) and the Microphone permission. Mysli asks for Microphone the first time you start a recording.

### Experimental Teams speaker names

This feature is off by default. Its rules come from public source code and tests with fake Accessibility trees. **It has not been verified during a real Teams call.** Teams can change its UI, hide its speaking indicator, or keep the last speaker highlighted. Names can be missing or wrong.

To opt in, turn on **Teams speaker names** in Settings. It applies from the next recording. You can also run this command and restart Mysli before your next recording:

```bash
defaults write io.github.christianvilen.mysli teamsSpeakerNamesEnabled -bool true
```

Mysli reads this preference once when each recording starts.

While you record, Mysli reads candidate speaker indicators and participant labels from the Teams desktop app through Accessibility. It supports a narrow profile of English meeting controls and video-tile structure. It does not enable Accessibility flags, click controls, open chats, or request a new permission. If Accessibility is unavailable or the structure is unsupported, recording continues and the remote lines stay "Them".

After Stop, a remote segment can say `Aino (Teams)` when repeated observations support that name for at least 90% of the segment. Conflicts, uncertain observations, overlapping remote segments, and insufficient coverage keep "Them". Mysli does not guess from a roster, a muted microphone, a calendar, or a saved voice profile. The live draft and microphone Room labels stay unchanged. A Teams label alone does not establish who owns an action item.

Pause stops observation. Resume starts a new observation run, and final timestamps use the same three-second silence gaps as the audio. Mysli keeps at most 36,000 observations per recording. It stops collection at that limit and retains earlier evidence.

Observations stay in memory through the processing queue and disappear when that job finishes. Quit, a crash, or a retry before the transcript exists can lose them, so those lines fall back to "Them". Once names are in the heard transcript, Update Notes preserves them. Named labels in the final transcript go to the summary CLI with the rest of the transcript. No separate participant list, raw AX tree, or voice profile is saved.

If the feature was on and every remote line stayed "Them", a line near the top of `transcript.md` says why. It gives the most common reason, for example:

> Teams speaker names were on, but no remote line got a name. In 380 of 412 scans, no Teams window showed meeting controls with Hang up or Leave.

If Teams showed a name in some scans, the line says in how many scans instead.

Mysli also writes the scan results and their counts to the macOS log. To watch the lines while you record, run this command:

```bash
/usr/bin/log stream --predicate 'subsystem == "io.github.christianvilen.mysli" AND category == "teams"'
```

To see the lines of the last two hours, run this command:

```bash
/usr/bin/log show --last 2h --predicate 'subsystem == "io.github.christianvilen.mysli" AND category == "teams"'
```

Use the full path `/usr/bin/log`, because zsh has its own `log` command. These log lines hold only reason codes, counts, and scan times. They never hold a name or other text from Teams.

To turn the feature off for future recordings, turn off **Teams speaker names** in Settings, or run this command and restart Mysli:

```bash
defaults write io.github.christianvilen.mysli teamsSpeakerNamesEnabled -bool false
```

The [source research](docs/superpowers/research/2026-10-29-teams-open-source.md) and [read-only probe instructions](docs/superpowers/research/2026-10-29-teams-ax-feasibility.md) describe the remaining real-call check.

### Optional meeting context

You can give the summary background about project terms, vendors, and people. Create a short UTF-8 Markdown file, for example `~/meeting-context.md`:

```markdown
# Project context
- Konvio is the passenger portal project.
- Brightlane supplies the network equipment.
- Aino and Jyri work on the portal.
```

In **Settings…**, click **Choose…** beside **Background file**. You can also set the path in Terminal:

```bash
defaults write io.github.christianvilen.mysli meetingContextFile "$HOME/meeting-context.md"
```

Mysli reads the setting and file again each time it makes a summary, including **Retry Failed Meeting**, **Update Notes**, and **Update summary**. You can edit the file or change its path without restarting Mysli. Existing notes stay unchanged until a summary runs again. Update Notes is available through the known-word review flow described above.

The whole accepted file goes to the CLI provider on every use: Google for `agy`, or Anthropic for `claude`. If both CLIs run with Automatic, the context can reach both providers. This includes people and terms that the transcript does not mention. Choose the contents with that disclosure in mind. This file is separate from `knownWordsFile`, which sends only matching word forms, never the list's notes or dates.

The prompt treats context as background data, never as instructions. The transcript and your typed notes take priority over background. Background must not add unsupported decisions, action owners, or other claims. An action owner needs explicit support in the transcript or typed notes, or remains "Unclear". Context does not change the transcript. The CLI still runs in an empty working folder with the existing fixed PATH, invocation options, fallback order, and ten-minute timeout. Passing context adds no tool access or project-file access.

The file must be no larger than **16 KiB (16,384 bytes)**, measured as UTF-8 bytes. This keeps the background short and limits how much data each prompt adds. Mysli reads at most one byte beyond the cap to detect an oversized file. It skips the whole file if it is too large; it never sends a truncated version. An unset or empty path, a missing file, or an empty or whitespace-only file adds no context block. An unreadable file, invalid UTF-8, a NUL byte, or a path that is not a regular file also adds no block. Mysli logs those errors and oversized files to the macOS log, without the file contents, and continues the summary without context.

To stop sending context, click **Clear** beside **Background file** in Settings. You can also remove the setting in Terminal:

```bash
defaults delete io.github.christianvilen.mysli meetingContextFile
```

This leaves your file in place. It does not remove context already sent to a provider or saved in `agy` history.

## Logs

Choose **Show Log…** in the menu, immediately after **Settings…**. The window
starts with logs from this launch. You can select Today, Last 7 days, or Everything
kept, then filter by app area or show errors only. It shows the newest 5,000 matching
lines and refreshes every two seconds while open. Scroll up to read older text
without following new lines. Press **Command-F** to open the find bar.

**Copy All** copies the displayed lines. **Save…** exports those same lines to a
text file. **Delete All Logs** asks for confirmation, then removes Mysli's daily
log files. New log messages create a file again. This does not remove macOS unified
logs.

Daily files are in `~/Library/Logs/Mysli/`, with access limited to your account.
At launch and at the first message of each new day, Mysli removes files older
than 14 days. It also removes the oldest files above a 20 MB total, while keeping
today's file even if it exceeds that limit.

Participant names, transcript text, known words, meeting context, error descriptions,
and summary-tool output stay private. Logs replace private values with `<private>`
before sending a message to either output. Fixed reasons, error codes, and approved
file paths remain visible. Full summary-tool failures remain in the meeting's
`error.md`.

To view live messages through macOS logging, run:

```sh
/usr/bin/log stream --predicate 'subsystem == "io.github.christianvilen.mysli"' --info
```

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 26+ (to build)

## Installation

### Homebrew (Recommended)

```bash
# Tap the repository
brew tap ChristianVilen/mysli

# Homebrew 7 and later load casks only from taps you trust
brew trust --cask christianvilen/mysli/mysli

# Install the app
brew install --cask mysli
```

**Important**: Since this is an unsigned app from an untrusted developer, you'll need to trust it:

```bash
# Remove the quarantine attribute (replace with actual path if different)
sudo xattr -d com.apple.quarantine /Applications/Mysli.app
```

Alternatively, you can use the GUI method:
1. Try to open Mysli from Applications
2. When blocked, go to **System Settings → Privacy & Security**
3. Click **"Open Anyway"** next to the Mysli warning

### Manual Installation

1. Download the latest `.zip` from [GitHub Releases](https://github.com/ChristianVilen/mysli/releases/latest)
2. Unzip and move Mysli.app to your Applications folder
3. Run the same trust command above

## Build & Run

1. Open `Mysli.xcodeproj` in Xcode 26 or later
2. Select the `Mysli` scheme and your Mac as the destination
3. `Cmd+R` to build and run

## Permissions

Screen Recording lets Mysli take screenshots and record the sound of a call for Meeting Notes. Accessibility lets it move windows and paste from clipboard history. On first launch, a setup window explains these permissions. Grant the permissions for the features you use; each row updates after you allow it in System Settings. Open the window again from **Permissions…** in the menu. A red dot in the bottom-left corner of the menu bar icon means an Accessibility or shortcut problem. An orange dot in that corner means Screen Recording is missing, when no red warning is present.

### Accessibility (window tiling and automatic paste)
Accessibility lets Mysli move and resize windows and paste items from clipboard history. The optional Teams speaker-name feature also uses it to read meeting UI. Registering the shortcuts does not need this permission.

**System Settings → Privacy & Security → Accessibility** → Enable Mysli

Mysli detects the permission when it becomes active or you open its menu. You do not need to restart it.

### Screenshot shortcut setup

Mysli keeps `Shift+Command+3` and `Shift+Command+4`. If macOS already uses them, Mysli opens the Permissions page with screenshot setup instructions once and lists the conflicts in its menu. Permission checks and shortcut setup share the same page. Choose **Open Keyboard Settings…**, then **Keyboard Shortcuts → Screenshots**, and turn off the matching macOS shortcuts:

- **Save picture of screen as a file** — `Shift+Command+3`
- **Save picture of selected area as a file** — `Shift+Command+4`

Mysli retries within a few seconds. The menu warnings disappear when the shortcuts are ready. It does not change system settings for you. You can return to the instructions through **Settings…** in the menu, on the **Permissions** page.

To keep the macOS screenshot tool instead, turn off **Use Mysli for screenshots** in Settings. Mysli then releases both shortcuts and shows no conflict for them.

All Mysli shortcuts use registered macOS hotkeys instead of a keyboard event tap. The menu lists registration failures for each shortcut; other registered shortcuts remain available. If a shortcut cannot be released, Mysli reports it and retries while running. Opening clipboard history and pasting are separate operations, so automatic paste can still fail in protected fields.

### Screen Recording (required)
ScreenCaptureKit requires screen recording permission to capture screen content. Meeting Notes also needs it to record the sound your Mac plays.

**System Settings → Privacy & Security → Screen Recording** → Enable Mysli

Two macOS quirks to expect: the first capture can require one quit-and-reopen of Mysli before the grant takes effect, and roughly every month macOS makes every screenshot app ask again for screen recording. Neither is something Mysli can turn off.

### Microphone (Meeting Notes)
Microphone lets Mysli record your side of a meeting. Only Meeting Notes needs it, so the setup window does not open for it at launch. Mysli shows the macOS prompt the first time you choose **Start Recording Meeting**. If you said no, an alert offers **Open Permissions**; there, **Grant** opens the Microphone pane. Until you are asked, the Microphone row shows "–" and **Allow** instead of ❌, because the permission is optional.

**System Settings → Privacy & Security → Microphone** → Enable Mysli

## Usage

1. Launch Mysli — it appears as a camera icon in the menu bar
2. Press `Shift+Command+3` to capture the full screen (the screen where your cursor is) — a flash animation confirms the capture
3. Press `Shift+Command+4` anywhere
3. Click and drag to select the area you want to capture
4. Release the mouse — the screenshot is saved and copied
5. A thumbnail preview appears in the bottom-right corner for 5 seconds
6. Click the thumbnail to open the editor — draw on the screenshot with freehand red lines, or press **Crop** and drag a box over the part you want to keep (drag the handles to resize, drag inside to move, click outside to remove the box)
7. Click **Done** to save the edited version (overwrites the file and updates the clipboard)
8. Click the **trash icon** on a thumbnail or **Delete** in the editor to delete the screenshot file and clear the clipboard
9. Press `Escape` to cancel a selection

## Screenshots Location

Screenshots are saved to `~/Screenshots/` with the naming convention:

```
Screenshot_2026-02-23_at_14-30-00.png
```

The folder is created automatically if it doesn't exist.

## Menu Bar Options

The menu has one group for each tool, with the tool's colored icon.

- **Screenshots**: **Capture Area** and **Capture Screen** work even when **Use Mysli for screenshots** is off. They show their shortcuts only while Mysli owns them.
- **Clipboard**: **Show Clipboard History** opens the history panel. It is disabled while clipboard history is off.
- **Windows**: **Window Tiling** turns the tiling shortcuts on and off. It saves the same preference as the switch in Settings.
- **Keep Awake** keeps the Mac awake for 30 minutes, 1, 2, or 4 hours, or until turned off. **Keep screen on** controls whether the display stays awake too. **Turn Off** ends the session.
- **Start Recording Meeting** and **Stop Recording Meeting** start and stop a meeting recording. While Mysli records, a line above them shows the recorded time, and "Paused" while the recording is paused. While Mysli makes notes, a line shows the step and how many meetings wait.
- **Pause Recording** or **Resume Recording**, **Show Meeting Controls**, and **Restore Default Position** appear while a meeting records or is paused.
- **Check Words** appears when meetings have words to check, with their number. It opens the review window on the oldest of those meetings.
- **Retry Failed Meeting** appears when a meeting's transcription or summary failed.
- **Open Meetings Folder** opens the folder that holds the meeting notes.
- **Settings…** opens the shared window. Command-comma opens it too while Mysli is active, and Command-W closes it. Changes save immediately. The permission checks and the screenshot shortcut setup are on its **Permissions** page.
- **Show Log…** opens the log window.
- **Quit Mysli** — Exit the app

## Settings

Open **Settings…** in the menu to change preferences and find setup or help. The sidebar has four pages:

- **Settings** has General, Screenshots, and Meeting Notes groups.
- **Features & instructions** lists keyboard shortcuts and explains each feature.
- **Permissions** shows live access checks, Grant buttons, and screenshot shortcut setup. Mysli opens this page when required access is missing at launch.
- **Help & feedback** opens GitHub to report a bug or send feedback. You review the message before sending it.

Command-comma always selects Settings. Opening a page does not change preferences.

| Preference | Default and choices |
|---|---|
| Launch at login | Current macOS login-item state. A failed change shows the error and the actual state. |
| Use Mysli for screenshots | On. Off releases `Shift+Command+3` and `Shift+Command+4` to macOS. |
| Enable window tiling | On |
| Record clipboard history | On |
| Show thumbnail for | 5 seconds. Choices are 3, 5, 15 seconds, and Forever. Existing custom values stay intact until changed. |
| Meetings folder | `~/Meetings`. Choosing another folder does not move existing meetings. |
| Summary tool | Automatic tries Antigravity, then Claude Code. Antigravity (agy) and Claude Code (claude) each use only that tool. |
| Background file | None. Choose an optional file, or Clear the preference without deleting the file. The complete accepted file goes to the selected provider with the transcript. |
| Calendar recording reminders | Off. Turning it on asks for Calendar and notification access. A line under the switch says what to allow when access is missing. |
| Teams speaker names | Off. Experimental. Applies from the next recording. |

The summary tool is read when each queued job starts. A running job keeps its choice. Opening Settings does not write preferences.

## File Structure


```
Mysli/
├── main.swift           # App entry point
├── AppDelegate.swift    # Menu bar setup, wires hotkey → overlay → capture → thumbnail → editor
├── SettingsWindowController.swift # Native Settings form and actions
├── OrdinaryWindowActivation.swift # Shared activation while ordinary windows are open
├── HotkeyManager.swift  # Desired shortcuts, feature toggles, retry and wake recovery
├── HotkeyShortcut.swift # Shortcut definitions and registration failures
├── HotkeyRegistration.swift # Registration state, reconciliation, conflict checks and failed-release recovery
├── CarbonHotkeyAPI.swift # Injectable macOS calls
├── HotkeyHealth.swift   # Permission and shortcut issues displayed by the menu
├── OverlayWindow.swift  # Full-screen transparent overlay window
├── SelectionView.swift  # Mouse drag selection with dimmed background + dimensions
├── CaptureManager.swift # Screen capture, save to disk, clipboard, delete
├── FlashView.swift      # White flash animation on screen after full-screen capture
├── ThumbnailPanel.swift # Floating preview panel after capture (with delete)
├── ThumbnailStackManager.swift # Manages stacking of multiple thumbnail panels
├── CombineButton.swift  # Floating "Combine" button between adjacent thumbnails
├── DrawingView.swift    # Freehand red drawing on screenshot image
├── EditorWindow.swift   # Centered modal for annotating screenshots
├── WindowTilingController.swift # Ties tiling hotkeys to the layout engine and window control
├── TilingLayoutEngine.swift  # Pure layout math for left/right/maximize tiling
├── TilingScreenRules.swift # Screen-picking + windows-per-screen counting, for the Stage Manager check
├── StageManagerDetector.swift # Reads whether Stage Manager is turned on
├── AccessibilityWindowControl.swift # Reads/moves the focused window via the Accessibility API
├── WindowListProvider.swift  # Lists on-screen windows via the window server
├── ScreenCoordinates.swift   # Shared top-left/bottom-left coordinate flip
├── MeetingFolder.swift       # One meeting on disk and the rule that reads its stage from the files
├── Transcript.swift          # Merges the two tracks, drops echoes, writes transcript.md
├── MeetingAudioCapture.swift # Records the microphone and system audio into two CAF files
├── MeetingTranscriber.swift  # The transcriber seam and the fallback, Apple's SpeechTranscriber
├── WhisperKitTranscriber.swift # On-device transcription with WhisperKit: model download, languages, silence filter
├── ModelInstall.swift        # Downloads a model once into its own folder, shared by Whisper and SpeakerKit
├── RoomLabels.swift          # The voices on the microphone track and the rule that gives each line one voice
├── SpeakerKitRoomLabeller.swift # Tells apart the voices in the room with SpeakerKit: model download, diarization
├── MeetingSummarizer.swift   # Runs agy or claude for the summary, writes summary.md
├── MeetingProcessor.swift    # Transcribes, then summarizes, from wherever a meeting stopped
├── MeetingRecorder.swift     # Records a meeting: start, pause, stop, the live transcript, and what the floating panel shows
├── MeetingNotesController.swift # Meeting Notes menu section and the processing queue
├── Corrector.swift           # Finds and replaces the confirmed wrong forms of known words
├── KnownWords.swift          # Reads the list of known words and adds a line to it
├── KnownWordsFile.swift      # The list of known words on disk, written under a lock
├── WordReview.swift          # Which suspect words become questions, and a meeting's questions and skips
├── WordReviewController.swift # The review window's state and its writes
├── WordReviewWindow.swift    # The review window (Check Words)
├── Info.plist           # App config (LSUIElement, screen capture and microphone usage)
└── Mysli.entitlements    # Entitlements (sandbox disabled)
```

## Known Limitations

- Turn off the matching macOS screenshot shortcuts to let Mysli register `Shift+Command+3/4`. With those macOS bindings off, quitting Mysli leaves those two shortcuts unassigned until you restore them in System Settings.
- `Ctrl+Option+Left/Right/Return` are intercepted globally while window tiling is enabled, even inside apps that use those same keys for something else. Clear **Enable window tiling** in Settings to give the keys back to other apps.
- `Shift+Command+C` is intercepted globally while clipboard history is enabled, including in apps that use it for something else. Clear **Record clipboard history** in Settings to give the key back.
- The automatic paste can't reach password fields or apps that block synthetic key events. The item is still on the clipboard, so pasting it by hand (`Cmd+V`) works.
- No preferences UI for changing the shortcut keys, including the window tiling hotkeys
- Some windows can't be tiled — apps that don't let their windows be moved or resized through the Accessibility API, and Mysli's own windows. The hotkey then does nothing; there is no error message.
- Meeting Notes transcribes one language per meeting, set with `meetingLocale` (US English by default).
- Remote lines use "Them" unless experimental Teams observations support a name. Teams compatibility remains unverified, and unsupported layouts keep "Them". Room labels do not say which voice is you.
- On speakers, a repeated line of fewer than 3 words can stay in the transcript as yours.
- The live transcript works only for a language whose Apple speech model is already on your Mac. There is none for Finnish.
- The macOS microphone indicator stays on while a meeting recording is paused.
- Other people can see the meeting panel when you share your screen. macOS has no supported way to keep a window out of a screen share.
- A meeting recording is tied to a display. If that display goes away (for example, the external monitor of a closed laptop), the recording stops, Mysli says so, and it makes notes from what it recorded.
- While `agy` is not logged in, it waits about 60 seconds before it fails, so the summary comes later. Mysli writes why it skipped `agy` to the system log.
- `agy` has no option that turns its tools off. Mysli runs it with `--sandbox` and tells it not to use tools or follow instructions in the transcript, but only your own `agy` configuration (for example a pre-tool hook) can block its tools. `claude` runs with every tool turned off.

## Testing

Press Cmd+U in Xcode, or run `xcodebuild -project Mysli.xcodeproj -scheme Mysli test`. The tests use fakes and temporary folders. They never capture the screen, touch your meetings folder, or download a model.

The `Real*Tests` classes run the real models on audio that you choose, and the picture tests write PNG files of the windows. They are skipped unless you set their environment variables. The comment above each of them gives the command.

## Acknowledgements

Meeting Notes transcribes with [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) (`argmaxinc/argmax-oss-swift`), which is under the MIT License.

Room labels use SpeakerKit from the same package (MIT License) and its models, [`argmaxinc/speakerkit-coreml`](https://huggingface.co/argmaxinc/speakerkit-coreml) by Argmax, under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The models are built from [pyannote segmentation-3.0](https://huggingface.co/pyannote/segmentation-3.0), [WeSpeaker](https://github.com/wenet-e2e/wespeaker), and [VBx](https://github.com/BUTSpeechFIT/VBx). Mysli downloads them unchanged.
