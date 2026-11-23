# Mysli

Mysli is a macOS menu bar app with six tools: screenshots, clipboard history, window tiling, Keep Awake, meeting notes, and dictation. The name is Finnish for muesli.

Website: [christianvilen.github.io/mysli](https://christianvilen.github.io/mysli)

## Install Mysli

Mysli needs macOS 26 (Tahoe) or later.

```bash
brew tap ChristianVilen/mysli

# Homebrew 7 and later load casks only from taps that you trust
brew trust --cask christianvilen/mysli/mysli

brew install --cask mysli
```

To install by hand, download the latest `.zip` from [GitHub Releases](https://github.com/ChristianVilen/mysli/releases/latest), unzip it, and move `Mysli.app` to the Applications folder.

Mysli is not notarized, so macOS blocks its first launch. Remove the quarantine mark:

```bash
sudo xattr -d com.apple.quarantine /Applications/Mysli.app
```

You can also open Mysli once, then go to **System Settings → Privacy & Security** and click **Open Anyway**.

## Set up Mysli

The first launch shows three steps:

1. **Welcome.** Click **Get Started**.
2. **Choose your tools.** Screenshots, Clipboard, Windows, Keep Awake, and Meetings start selected. Dictation and **Calendar reminders** start off. A tool that you clear turns off and releases its shortcuts.
3. **Allow access.** Grant the permissions for your tools. **Finish** works even when some permissions are missing.

Mysli saves the step and your choices. If macOS asks you to quit and reopen Mysli after you grant Screen Recording, setup continues at the saved step.

**Skip setup** turns on the five default tools and leaves Dictation off. You can change the tools later in **Settings…**. After setup, Mysli opens the **Permissions** page at launch when an enabled tool lacks access.

Mysli has no Dock icon while only the menu is in use. The Dock icon appears while a Mysli window is open.

## Screenshots

| Shortcut | Action |
|---|---|
| `Shift+Command+4` | Drag to capture an area. Press Space before you click to capture a window. Escape cancels. |
| `Shift+Command+3` | Capture the screen under the pointer. |

Mysli saves each screenshot as a PNG in `~/Screenshots/`, for example `Screenshot_2026-02-23_at_14-30-00.png`, and copies it to the clipboard.

A thumbnail then appears in the bottom-right corner for 5 seconds. **Show thumbnail for** in Settings changes the time to 3, 5, or 15 seconds, or Forever. Click the thumbnail to open the editor:

- Draw on the screenshot in red. **Undo** removes the last stroke.
- Click **Crop** and drag a box. Drag its handles to resize it, or drag inside it to move it.
- **Done** saves the result over the file and updates the clipboard.
- The trash button, on the thumbnail or in the editor, deletes the file and its clipboard entry.

Up to five thumbnails stay in a stack. Click **Combine** between two adjacent thumbnails to join those screenshots into one image.

If macOS already uses the two shortcuts, Mysli lists the conflict in its menu and opens the shortcut setup once. Choose **Open Keyboard Settings…**, then **Keyboard Shortcuts → Screenshots**, and turn off these two macOS shortcuts:

- **Save picture of screen as a file**
- **Save picture of selected area as a file**

Mysli tries again within a few seconds. It never changes macOS settings for you. To keep the macOS screenshot tool, turn off **Use Mysli for screenshots** in Settings.

## Clipboard history

Press `Shift+Command+C` to open a list of recent copies, newest first. Type to filter the list, select an item with the arrow keys, and press Return to paste it into the app that you used. For formatted text, Mysli first asks whether to keep the formatting. Paste without formatting is selected, so a second Return pastes plain text.

Mysli records text and images, including its own screenshots. It skips empty copies, text that is only white space, and copies that a password manager marks as concealed or transient.

The history stays in memory and is never written to disk, so a restart empties it. It holds at most 100 items and about 100 MB of images, and it drops the oldest images first. Mysli does not record an item over 50 MB.

Turning **Clipboard history** off in Settings clears the history and releases the shortcut.

## Window tiling

| Shortcut | Action |
|---|---|
| `Control+Option+Left Arrow` | Fill the left half of the display. Press again to move to the next display. |
| `Control+Option+Right Arrow` | Fill the right half of the display. Press again to move to the next display. |
| `Control+Option+Return` | Maximize the window. Press again to restore its previous frame. |
| `Control+Option+C` | Center the window without changing its size. |

With more than one display, Mysli tiles the window on the screen that it overlaps the most. Screenshots follow the pointer instead.

When Stage Manager is on and the screen shows two or more windows, maximize leaves room for the Stage Manager strip on the left and a small gap on the other sides. Half tiling never leaves this room.

Turn **Window tiling** off in Settings, or in the menu, to release the shortcuts.

## Keep Awake

In the **Keep Awake** section of the menu, choose 30m, 1h, 2h, 4h, or ∞ (until you turn it off). **Turn Off** ends the session. A blue dot at the lower right of the menu bar icon marks an active session, and the menu shows the time left.

**Keep screen on** starts on. Turn it off to let the display sleep and lock on its normal schedule. The change applies to an active session without restarting its timer.

Closing the lid of a laptop still sleeps the Mac, unless the laptop has power and an external display.

## Meeting notes

Mysli records a call, transcribes it on your Mac, and asks an AI command-line tool for a summary. Each meeting gets a folder, for example `~/Meetings/2026-10-23_14-02/`, with `transcript.md` and `summary.md`.

### Before the first meeting

- Install Antigravity (`agy`), Claude Code (`claude`), or both in `/opt/homebrew/bin`, `/usr/local/bin`, or `~/.local/bin`. Log in to each tool once in Terminal. If neither tool is found, Settings and the setup window show a warning.
- Allow Microphone and Screen Recording access. Screen Recording is how Mysli records the sound that your Mac plays.
- The first meeting downloads the Whisper model (about 1.5 GB) and the room-label model (about 11 MB) to `~/Library/Application Support/Mysli/`. After that, transcription needs no network. Mysli keeps both models out of Time Machine backups.

### Record a meeting

Choose **Start Recording Meeting** in the menu. Mysli records your microphone and the sound that your Mac plays, so any call app works. If the recording cannot start, an alert gives the reason.

A small panel floats near the top-right corner of the screen. It has the recorded time and buttons for Pause, Stop, notes, and the live transcript. Pause and Stop leave the keyboard with your call app.

- Drag the panel to move it. **Restore Default Position** in the menu puts it back.
- **Hide panel** hides it while the recording continues. **Show Meeting Controls** in the menu shows it again.
- The menu bar icon shows a red dot while Mysli records and two white bars while the recording is paused.
- The menu shows **Microphone** and **Mac audio** level meters while it is open. An empty meter means silence, no incoming audio, or a paused recording.

**Pause** leaves part of a call out. Mysli saves no audio until you resume. The macOS microphone indicator stays on, because Mysli keeps the capture running so that Resume always works. Each time you resume, Mysli adds 3 seconds of silence to the audio files and the transcript. The timer excludes those gaps.

**Stop** ends the recording. Mysli starts the transcript and summary once your notes are saved. A notification tells you when the notes are ready. Click it to open the summary, or the review window when there are words to check. If the recording stops by itself, for example because its display went away, the panel gives the reason and stays until you close it.

### Write your own notes

While recording or paused, opening the notes also shows the live transcript above them. Other people can see both when you share that screen. To open the notes, click the notes button in the panel or choose **Write Meeting Notes…** in the menu.

- Each row gets its timestamp when you first write in it. Return starts a new row, and Shift+Return adds a line inside the row.
- Paste or drop a screenshot into a row to attach it. Mysli saves the image in the `attachments` folder of the meeting and links it from `notes.md`.
- Each edit saves to `notes.md` in the meeting folder. Notes hold up to 64 KiB of text.
- You can write while the recording is paused and after Stop. Notes that you add after Stop say **After recording**.
- **Recent Meeting Notes** in the menu reopens the last five meetings and any unsaved drafts.

The first summary uses the transcript and your saved notes. Later edits do not change the summary until you choose **Update summary**, which rewrites only `summary.md`. If the update fails, the previous summary stays.

If a save fails, the window keeps your draft and offers **Retry save**. After Stop, a successful save lets the transcript and summary start. If `notes.md` changed in another editor, copy the draft text that you need before you choose **Reload saved notes**. Quit asks before it discards unsaved text.

### Read the live transcript

Click the transcript button in the panel to open a drawer with a rough live draft. It marks each message "Me" or "Them" with a time. Mysli never saves the draft. The full transcript replaces it after Stop.

- Other people see the panel when you share your screen, so the drawer starts closed in every meeting.
- Scrolling back or selecting text stops the automatic scroll. **Return to live** starts it again.
- The drawer tells you when the draft is 4 seconds or more behind the call.

The live draft uses Apple speech recognition, and only for a language whose Apple model is already on your Mac. Mysli never downloads a model for it. Languages that Apple does not support, such as Finnish, get no live draft. The recording and the full transcript are not affected.

### Transcript and summary

Mysli transcribes with Whisper (the `large-v3-v20240930_turbo` model, through WhisperKit). If Mysli cannot load the model, or Whisper does not know the language, Apple speech recognition does the work instead. The top of the transcript names the transcriber and gives the reason for a change.

The **Summary tool** setting selects the AI tool. **Automatic**, the default, tries `agy` first and uses `claude` if `agy` fails. Mysli reads the setting when each queued job starts, and a running job keeps its choice. Claude Code summaries use Sonnet with medium effort.

In the transcript, "Them" is everyone else on the call, taken from the sound that your Mac plays. Your microphone hears you and anyone in your room:

- With one voice in the room, the microphone lines say "Me".
- With more voices, Mysli labels them "Room 1", "Room 2", and so on, in the order that they first speak. It never guesses which voice is you.
- Two similar voices can share a label, and one person can get two. A voice with fewer than 5 words takes the label of the nearest voice in time.
- Mysli does not separate the voices on a microphone track longer than 3 hours.

Use headphones for the cleanest transcript. On speakers, your microphone also hears the other people. Mysli removes those repeated lines when it finds them.

Mysli asks the summary tool to name an action owner only when the transcript or your notes say who will do the task. Otherwise, the prompt asks for "Unclear". Your notes can supply decisions and owners that the transcript lacks. The prompt asks the tool to show conflicts between the two sources.

### What leaves your Mac

Mysli keeps audio on your Mac. Before it asks for a summary, it moves the audio files to the Trash. It keeps them if it found no speech and you wrote no notes.

The summary tool gets:

- the transcript, including any Teams speaker names, without its notes on the transcriber
- your saved notes: the time and the text of each row, and the file names of its screenshots, but never the images
- each known word that occurs in the transcript, as its forms only
- the whole [meeting context file](#give-the-summary-background), if you set one

The notes and dates in your known-words list stay on your Mac. Your typed notes are evidence for the summary, never instructions to the tool.

`agy` sends this input to Google and keeps the prompt in its conversation history. `claude` sends it to Anthropic and saves no session. With **Automatic**, the input can reach both providers. To use one provider for each summary, choose **Antigravity (agy)** or **Claude Code (claude)** under **Summary tool**. Mysli uses only the selected tool for that job, even if it fails.

Do not put the meetings folder in `~/Documents` or `~/Desktop` when iCloud syncs them, because the audio then leaves your Mac.

### Change the folder or the language

To keep new meetings in another folder, click **Choose…** beside **Meetings folder** in Settings. Mysli does not move existing meetings, and a meeting in progress finishes in its original folder.

Mysli transcribes US English by default and transcribes one language for each meeting. To change the language, quit Mysli and run this command in Terminal with the language tag you want.

```bash
defaults write io.github.christianvilen.mysli meetingLocale de-DE
```

Reopen Mysli after you run the command. Whisper uses only the language part of the tag, so `fi-FI` gives Finnish. The Apple alternative needs a tag that Apple supports exactly, such as `en-GB`, `de-DE`, or `ja-JP`. The summary uses the language of the transcript.

### Fix names and terms

Speech recognition often spells names and terms wrong. Mysli keeps a list of known words in `known-words.md` in the meetings folder. To use another file, quit Mysli and run this command in Terminal with the path to the file.

```bash
defaults write io.github.christianvilen.mysli knownWordsFile ~/path/to/list.md
```

Reopen Mysli after you run the command. Each line has the wrong form, an arrow, and the right form in bold, for example `- Convio → **Konvio** ✓`. Mysli replaces a wrong form in the transcript only when its line has ✓. Lines without ✓ only help the summary. Mysli adds lines to the list and never changes or removes one.

The summary tool also reports words that it suspects are wrong. Mysli asks you about up to 5 of them for each meeting. Choose **Check Words** in the menu, then type the right word and click **Save**, or click **It Is Correct as Heard** or **Skip**.

- An answer goes into the list, and Mysli stops asking about that word in every meeting.
- A name always gets ✓. Another word gets no ✓ when its wrong form is ordinary words of the language, for example "my key".
- After the last word, **Update Notes** makes the transcript and the summary again with your answers.

Update Notes builds `transcript.md` again from the text that speech recognition wrote. It replaces changes that you made to `transcript.md` by hand. To fix a word, add it to the list instead.

### Give the summary background

A context file tells the summary about project terms, vendors, and people:

```markdown
# Project context
- Konvio is the passenger portal project.
- Brightlane supplies the network equipment.
- Aino and Jyri work on the portal.
```

Click **Choose…** beside **Background file** in Settings. **Clear** removes the setting and leaves the file in place. Mysli reads the file again for each summary.

The whole file goes to the provider with every summary, including people and terms that the meeting did not mention. Choose the contents with that in mind. Context that a provider already received stays there after you clear the setting.

Mysli tells the summary tool to use the file as background and take decisions and action owners from the transcript or your notes. The file must be UTF-8 and no larger than 16 KiB. Mysli skips a larger or unreadable file and never sends a part of one.

### Get calendar reminders

**Calendar reminders** on the Meetings page starts off. When it is on, an event offers **Start Recording**, then **Stop Recording** or **Continue Recording** at its end. Mysli never starts or stops a recording by itself.

- **Remind me** sets the reminder to the event start, or to 1, 2, or 5 minutes before it.
- **Remind for** can limit reminders to events with a Teams, Google Meet, or Zoom link.
- A recording that starts from a reminder uses the event title in the menu and the notes.

The first use asks for Calendar and notification access. See the [integration contract and limits](docs/calendar-recording-reminders.md).

### Name Teams speakers (experimental)

**Teams speaker names** in Settings starts off. When it is on, Mysli reads speaker indicators and participant labels from the Teams desktop app through Accessibility while you record. A final remote line can show `Aino (Teams)` in the live transcript and in the transcript after Stop. Draft remote rows show "Them".

Treat the names as best effort. Names can be missing or wrong. The video gallery view and names in either transcript still need a real-call check. See [Teams speaker names](docs/teams-speaker-names.md) for what Mysli reads, when a line gets a name, and how to find out why no name appeared.

### When a meeting fails

- If a step fails, the meeting folder gets an `error.md` with the reason, and the menu shows **Retry Failed Meeting**. Retry continues from the failed step.
- If Mysli quits or crashes, it resumes pending work at the next launch if **Meetings** is on and the recording is in the selected meetings folder.
- If nobody spoke and you typed no notes, Mysli reports that it found no speech and keeps the audio. A silent meeting with notes still gets a summary.
- If a model download fails, that meeting uses Apple speech recognition or keeps "Me", and the next meeting tries again.
- To give up on a meeting, delete its folder. **Open Meetings Folder** opens the folder that holds them.

Turning **Meetings** off hides its menu section and turns reminders off. An active recording and queued work continue.

## Dictation

Hold a key, speak in English, and release the key. Mysli transcribes your words with Whisper, sends the text to Claude Haiku for polish, and pastes the result.

### Turn dictation on

1. Turn on **Dictation** on its Settings page.
2. Allow Microphone and Accessibility access.
3. Choose the key in **Hold to dictate**. Fn is the default and also needs Input Monitoring access. Control + Option + D does not.
4. For Fn, open **Keyboard Settings** and set **Press 🌐 key to** to **Do Nothing**. Mysli never changes macOS settings.

Polish needs Claude Code (`claude`) in `/opt/homebrew/bin`, `/usr/local/bin`, or `~/.local/bin`, logged in once in Terminal. Without it, Mysli pastes the text that it cleaned on your Mac, and the menu and Settings show a warning.

### Dictate

- A hold under 0.3 seconds does nothing. Escape cancels. A hold stops after two minutes.
- A pill near the bottom of the screen shows the microphone level. It shows a triangle during the last ten seconds.
- After the paste, a triangle means that the text has no Claude polish. A cross means an error.
- **Paste last dictation again** in the menu pastes the last text again without a new request.
- Mysli restores your previous clipboard after the paste, unless you copied something new. Dictation adds nothing to clipboard history.

These spoken words become formatting, with or without Claude:

| Say | Result |
| --- | --- |
| "new line" | One line break |
| "new paragraph" | A blank line |
| "comma" | `,` |
| "period" or "full stop" | `.` |
| "question mark" | `?` |
| "exclamation mark" or "exclamation point" | `!` |
| "colon" | `:` |
| "semicolon" | `;` |

A phrase inside quotation marks stays as words. A shell command that Mysli recognizes, such as `git push`, keeps its words and does not go to Claude. Mysli never sends the Return key, but a pasted line break can submit input in a terminal.

Meetings and dictation share one Whisper model, which stays loaded while dictation is on. You can dictate during a meeting, but the meeting microphone also records those words.

### What dictation sends

Claude gets:

- the text that Mysli cleaned on your Mac, with spoken formatting already converted
- every correct spelling from the known-words list, without its notes, dates, or ✓ marks
- the name of the front app
- up to 500 characters before the cursor, while **Send text near the cursor** is on, as it is by default

Mysli never reads text from secure fields. Audio never leaves your Mac.

Audio, text, and Claude input and output stay in memory. Each request is a new Claude conversation with no tools and no saved session. If polish fails, changes the line breaks, or takes more than 2.5 seconds, Mysli pastes the text that it cleaned on your Mac.

## Settings

**Settings…** in the menu, or Command-comma, opens the Mysli window. It has a General page with **Launch at login**, one page for each tool, then Permissions and Help. Each tool page holds the switch of the tool, its settings, its shortcuts, and a guide. Changes save immediately. A tool that is off has no menu section.

**Search Settings**, or Command-F, finds a setting, a shortcut, a permission, or a guide. Search accepts partial words, common names such as "startup", and one typing mistake in a longer word.

## Permissions

| Tool or choice | Access |
|---|---|
| Screenshots | Screen Recording |
| Clipboard | Accessibility |
| Windows | Accessibility |
| Keep Awake | None |
| Meetings | Microphone, Screen Recording |
| Dictation | Microphone, Accessibility |
| Fn dictation | Input Monitoring also |
| Calendar reminders | Calendar, Notifications |

The **Permissions** page in Settings shows only the rows that your tools need, and the rows update while the page is open. Click **Allow** or **Grant** on a row. Mysli shows the system prompt or opens the corresponding settings pane.

- **Accessibility** lets Mysli move windows, paste clipboard items and dictation, and read text near the cursor. Mysli detects the grant without a restart.
- **Screen Recording** allows screenshots and the Mac audio track of a meeting. macOS can ask you to quit and reopen Mysli.
- **Calendar** lets Mysli read event titles and times. Mysli also looks in the notes, location, and URL of an event for a video link, and keeps only a yes or no. It never changes your calendar.
- **Notifications** is required only for calendar reminders. Other tools ask when you first start something that notifies.
- Teams speaker names uses Accessibility but adds no required row.

A red dot at the lower left of the menu bar icon means that an Accessibility grant or a shortcut is missing. An orange dot means that Screen Recording is missing.

The menu lists each shortcut that Mysli could not register. The other shortcuts keep working.

## Logs

**Show Log…** in the menu opens a log window that updates while it is open. Select this launch, Today, Last 7 days, or Everything kept, and filter by app area or show only errors. The window shows the newest 5,000 matching lines. Command-F opens the find bar.

**Copy All** and **Save…** export the lines that the window shows. **Delete All Logs** removes the daily files of Mysli, but not the macOS unified log.

The daily files are in `~/Library/Logs/Mysli/`, readable only by your account. Mysli removes files older than 14 days, and the oldest files above 20 MB in total.

Logs replace private values with `<private>`. Participant names, transcript text, known words, meeting context, error descriptions, and summary tool output are private. If initial processing fails, the meeting's `error.md` records the reason.

To watch the messages in the macOS log, run:

```bash
/usr/bin/log stream --predicate 'subsystem == "io.github.christianvilen.mysli"' --info
```

## Known limitations

- You cannot change the shortcut keys, except for the dictation key.
- Mysli takes its shortcuts in every app while the tool is on, also in apps that use the same keys. Turn the tool off to give the keys back.
- With the macOS screenshot shortcuts off, `Shift+Command+3` and `Shift+Command+4` do nothing after you quit Mysli. Turn them on again in System Settings.
- Password fields and apps that block simulated paste can prevent automatic paste. For clipboard history, the selected item stays on the clipboard, so you can press Command-V. For dictation, Mysli restores the previous clipboard contents. To try the dictation again, choose **Paste last dictation again**.
- Some windows cannot be tiled: windows of apps that refuse Accessibility moves, and the windows of Mysli. The shortcut then does nothing.
- On speakers, a repeated line of fewer than 3 words can stay in the transcript as yours.
- A meeting recording is tied to a display. If that display goes away, the recording stops and Mysli makes notes from what it has.
- While `agy` is not logged in, it waits about 60 seconds before it fails, so the summary comes later.
- `agy` has no option that turns its tools off. Mysli runs it with `--sandbox` and tells it not to use tools, but only your own `agy` configuration can block them. `claude` runs with every tool off.

## Build and test

Open `Mysli.xcodeproj` in Xcode 26 or later, select the `Mysli` scheme, and press Command-R. From Terminal:

```bash
xcodebuild -project Mysli.xcodeproj -scheme Mysli build
xcodebuild -project Mysli.xcodeproj -scheme Mysli test
```

The tests use fakes and temporary folders. They never capture the screen, touch your meetings folder, or download a model. The `Real*Tests` classes and the picture tests run only when you set their environment variables. The comment above each one gives its command.

`AGENTS.md` holds the rules for contributors, `CONTEXT.md` defines the terms, and `docs/superpowers/specs/` holds the feature designs.

## Acknowledgements

Meeting notes and dictation transcribe with [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift), under the MIT License.

Room labels use SpeakerKit from the same package and its models, [`argmaxinc/speakerkit-coreml`](https://huggingface.co/argmaxinc/speakerkit-coreml) by Argmax, under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The models are built from [pyannote segmentation-3.0](https://huggingface.co/pyannote/segmentation-3.0), [WeSpeaker](https://github.com/wenet-e2e/wespeaker), and [VBx](https://github.com/BUTSpeechFIT/VBx). Mysli downloads them unchanged.
