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

- **Icon.** A dark bowl heaped with five pieces, one for each tool: a crisp with crop corners (Screenshots), two oat flakes (Clipboard history), a square split in two (Window tiling), a coffee bean (Keep Awake), and a lingonberry (Meeting notes). The user chose this concept, "A", from three on 2026-11-04. `Mysli/AppIcon.icon` holds it as SVG layers in three groups, so Liquid Glass and the dark and tinted modes work. One design serves every size, so the pieces are large and have no fine strokes.
- **Menu bar icon.** A template image of the bowl, the split square, and the berry. The berry sits where the recording mark appears, so the mark covers it while Mysli records. The Keep Awake dot is fixed system blue, because the lingonberry accent would look like the recording mark.
- **Palette.** One warm palette for the app and the website. Light: oat `#F6F0E4`, cream `#EFE6D3`, rule `#E2D5BC`, toast `#6F5B47`, roast `#2E2118`, lingonberry `#B4233C`. Dark: `#1E1712`, `#2A211A`, `#3D3027`, `#B9A58E`, `#F3EADB`, lingonberry `#E5566B`. It replaces the "Cobalt" theme. The lingonberry is the app's accent color.
- **Window.** One sidebar page for each tool: General, Screenshots, Clipboard, Windows, Keep Awake, and Meetings, then Permissions and Help. Each tool page holds its switch, settings, shortcuts, and guide. The "Features & instructions" page goes away. The window keeps the standard macOS background. The sidebar uses AppKit's source-list table inside a sidebar split-view item, with native selection, focus, and resizing. The brand shows in the accent color, tool squares, and header.
- **Menu.** The dropdown stays an `NSMenu`, grouped by enabled tool, with native section headers and tool icons. Keep Awake uses a native section header for its changing session title. A disabled tool has no menu group. Settings… replaces "Mysli…" and "Permissions…".
- **Screenshots switch.** "Use Mysli for screenshots" gives Shift+Command+3 and 4 back to macOS when it is off.
- **Permissions.** Required access comes from enabled tools and the reminder choice, as listed below. Calendar is required only while reminders are on. Notifications has its own row in that case.
- **Website.** The hero gets the tagline. Features gets one block for each tool. The comparison table becomes "One app instead of five": one row for each tool, the separate app that people install for it today, and an honest note where Mysli does less.

## Onboarding

The approved reference is the Onboarding row of the [design canvas](https://claude.ai/artifact/KZMmW1CEbRR3djsF7jeFgb), with boards `OnbWelcome`, `OnbTools`, and `OnbPermissions`.

Onboarding uses the full width of the Mysli window without a sidebar. It keeps the standard macOS background, Liquid Glass, the lingonberry accent, and `MysliTool.icon(size:)` squares. A footer holds navigation and three progress marks.

1. **Welcome** shows the icon, tagline, and five tools, with Get Started and Skip setup.
2. **Choose tools** starts with all tools selected. Continue applies the choices and releases the shortcuts of disabled tools. Keep Awake and Meetings have their own preferences and page switches. Keep Awake off ends its session. Meetings off turns reminders off but leaves active recording and queued processing running.
3. **Allow access** shows only required permission rows, with current status and a count of allowed grants. A restored access step shows a welcome-back banner. Finish is available while access is missing.

Calendar reminders is an unchecked choice under Meetings. It is unavailable while Meetings is off. Continue applies it through `calendarReminders.setEnabled(_:)` when it differs from the saved preference. Only `setEnabled(_:)` changes the actual reminder preference. Calendar and Notifications rows grant access without enabling reminders.

`RequiredPermissions` supplies one list to onboarding, the Settings Permissions page, and the launch check. A shared permission appears once:

| Enabled tool or choice | Required access |
|---|---|
| Screenshots | Screen Recording |
| Clipboard | Accessibility |
| Windows | Accessibility |
| Keep Awake | None |
| Meetings | Microphone, Screen Recording |
| Calendar reminders | Calendar, Notifications |

Optional Teams speaker names does not add Accessibility to the list. The Permissions page includes the line "Turn on more tools to see their permissions." Screenshot shortcut guidance is hidden while Screenshots is off.

`Onboarding` saves progress in these defaults keys:

| Key | Saved value |
|---|---|
| `onboardingStep` | `welcome`, `tools`, or `permissions` |
| `onboardingTools` | Selected `MysliTool` raw values |
| `onboardingCalendarReminders` | Draft reminder choice |
| `onboardingFinished` | Whether Finish or Skip setup was clicked |

Continue saves the access step before it can request reminder permissions. A quit and reopen returns to the saved step and reads the current grants. Opening setup or refreshing it never writes preferences. The user's existing preferences have no finished mark, so onboarding appears once for this user too.

Finish replaces onboarding with the normal window pages. Skip setup finishes with all tools on and keeps the saved reminder setting. It does not apply an unsubmitted reminder choice. After setup, missing required access opens the Permissions page at launch.

## Order of work

The rename, icon, and initial app redesign land as commits on `main`, without pull requests. Onboarding uses the `onboarding` worktree and merges later with `workmux merge`. Each onboarding step needs full tests, `scripts/check-tests.sh`, a shown diff, and approval before its commit.

Each push to `main` runs `release.yml`, which publishes a release and updates the cask. Build Release, quit the running app, and replace `/Applications/Mysli.app` only after approval. Warn before each install that an ad-hoc build loses its grants. The push waits for the user's app test and separate approval.

1. The rename, with no change in behavior. The repo and tap renames happen with the first push.
2. The icon and the palette.
3. The app redesign.
4. The website.

The rename commit also fixes three old mistakes: the bundle ID in the website's `tccutil` command, the `/Applications/Ku-Ka.app` quarantine path, and the `KuKaUITests` line in `justfile`. It deletes `APP_STORE.md`, which describes notarization that was never set up.

Dated specs, plans, research, and `.claude/` notes are history and keep the old name.

## Manual checks still needed

Fakes and native pictures cover setup rules and layout. They do not prove these checks in the installed app:

- Complete onboarding and check that disabled tools lose their menu groups and shortcuts.
- Grant Screen Recording, quit and reopen when asked, and check the saved step and allowed rows.
- Check the Calendar and Notifications prompts after selecting reminders and clicking Continue.
- Check that the activation fix brings the window forward with Stage Manager on.
- Check the menu, normal pages, keyboard use, and VoiceOver.

The website work has not started.
