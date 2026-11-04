# Rename Ku-Ka to Mysli

Ku-Ka started as a screenshot tool. Its name is short for *kuvakaappaus*, Finnish for "screenshot". The app now also keeps the Mac awake, tiles windows, keeps a clipboard history, and records meetings, so the name no longer fits. The user decided the points below on 2026-11-04.

## Name and story

The new name is **Mysli**. In Finnish, *mysli* means muesli, a mix of many things. In Czech, *mysl* means "mind", and in Polish, *myśli* means "thoughts".

At least two open-source macOS meeting apps are called "Muesli" and call themselves Granola alternatives. The user accepted that risk. No app or Finnish trademark called "Mysli" was found. Nobody searched the PRH or EUIPO registers.

Mysli is a menu bar multitool. Meeting notes are its largest tool, but the story does not lead with them.

- Tagline: "A daily mix of Mac tools."
- Subline and GitHub description: "Screenshots, clipboard history, window tiling, Keep Awake and private meeting notes, in one menu bar app."
- Name note: "Mysli is Finnish for muesli: a mix of good things."

## Rename everything

"Ku-Ka", "KuKa", and "kuka" go out of the app, the repo, the website, and the release pipeline. No "formerly Ku-Ka" note stays.

| Thing | New value |
|---|---|
| Xcode project, targets, scheme, Swift module | `Mysli.xcodeproj`, `Mysli`, `MysliTests` |
| Source folders | `Mysli/`, `MysliTests/` |
| Bundle ID and log subsystem | `io.github.christianvilen.mysli` |
| Test bundle ID | `io.github.christianvilen.mysli.tests` |
| Application Support folder | `~/Library/Application Support/Mysli/` |
| Log folder and files | `~/Library/Logs/Mysli/Mysli-YYYY-MM-DD.log` |
| Test variables | `MYSLI_*`, passed as `TEST_RUNNER_MYSLI_*` |
| GitHub repo | `ChristianVilen/mysli` |
| Website | `christianvilen.github.io/mysli`. The old `/ku-ka` path returns 404. |
| Homebrew | tap `ChristianVilen/homebrew-mysli`, cask `mysli`, zip `Mysli.zip`. No rename file in the tap. |

The bundle ID does not follow a bought domain. A domain can expire, and the GitHub account stays.

### Keep reading the old file markers

Files on disk are the one exception. Meeting folders hold text that the app parses back, and the old text contains the brand:

- `notes.md` starts with `<!-- Ku-Ka notes v2 -->` and marks each row with `<!-- Ku-Ka row ` and `<!-- Ku-Ka end -->`.
- `transcript.md` has a speaker legend that says "Ku-Ka told the voices apart". `Transcript.contentForSummary` and `Transcript.isSilent` match each legend word for word.

New files get markers without a brand, so the next rename cannot break them:

- `notes.md` uses `<!-- notes v3 -->`, `<!-- row `, and `<!-- end -->`. The parser reads v2 and v3. The next save writes v3.
- New legends say "This Mac told the voices apart". The old legends stay as cases of `Transcript.Legend`.

The old marker strings stay in the parser only, with a comment that says why. A test reads a v2 file and a v3 file.

`known-words.md` gets a new section heading, `## Added from word review`. The lines that the app adds no longer end in "by Ku-Ka". The app never changes a line, so the user's existing heading is renamed by hand.

## Existing users

The user is the only user. The app has no import code. After the rename, these steps run once, by hand, on the user's Mac:

1. Copy the `com.kuka.screenshot` defaults into the new bundle ID. Set `meetingsFolder` to the new repo path.
2. Move `~/Library/Application Support/Ku-Ka/` to `Mysli/`. The Whisper models are about 1.5 GB.
3. Move `~/Library/Logs/Ku-Ka/` to `Mysli/` and rename the log files.
4. Rename the `## Added by Ku-Ka` heading in `known-words.md`.
5. Turn off the old login item, quit and delete `KuKa.app`, and reset the old privacy entries with `tccutil`.
6. Reinstall from the new tap and give the permissions again.
7. Rename `~/work/ku-ka` to `~/work/mysli` and move the Claude memory files.

The `aa-docs-meeting` skill in the AA knowledge base changes in the same step. It reads the new bundle ID, uses `mysli_meeting:` as its duplicate key, and the one note that uses `kuka_meeting:` changes with it.

## Look and feel

- **Icon.** A bowl with a mix of pieces. Each piece has a different shape and stands for one tool. The menu bar icon is the bowl outline, which leaves room for the status marks. Three SVG concepts come first. The chosen one becomes a layered Icon Composer `.icon` and a menu bar template image.
- **Palette.** One warm palette for the app and the website: oat and cream paper, dark-roast text, and one berry accent. It replaces the "Cobalt" theme.
- **Window.** One sidebar page for each tool: General, Screenshots, Clipboard, Windows, Keep Awake, and Meetings, then Permissions and Help. Each tool page holds its switch, settings, shortcuts, and guide. The "Features & instructions" page goes away.
- **Menu.** The dropdown stays an `NSMenu`, grouped by tool, with section headers and tool icons.
- **Website.** The hero gets the tagline. Features gets one block for each tool. The comparison table becomes "One app instead of five": one row for each tool, the separate app that people install for it today, and an honest note where Mysli does less.

## Order of work

The work lands as commits on `main`, without pull requests. Each push to `main` runs `release.yml`, which publishes a release and updates the cask. Nothing is pushed without the user's approval.

1. The rename, with no change in behavior. The repo and tap renames happen with the first push.
2. The icon and the palette.
3. The app redesign.
4. The website.

The rename commit also fixes three old mistakes: the bundle ID in the website's `tccutil` command, the `/Applications/Ku-Ka.app` quarantine path, and the `KuKaUITests` line in `justfile`. It deletes `APP_STORE.md`, which describes notarization that was never set up.

Dated specs, plans, research, and `.claude/` notes are history and keep the old name.
