# Settings window implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development. Use TDD for each behavior change. The parent owns design and review.

**Goal:** Move persistent menu controls to native Settings and add summary-tool selection.

**Architecture:** Settings owns persistence. A three-case SummaryTool value travels from job start through the processor to the summarizer. One window exposes preferences and sends typed effects to existing runtime owners.

**Tech Stack:** Swift, AppKit, XCTest.

**Spec:** docs/superpowers/specs/2026-10-29-settings-window-design.md

**Completion:** Implemented and independently reviewed. See [verification](../verification/2026-10-29-settings-window.md) for final test results, the native image, remaining live checks, and the menu-test sequence deviation. The checklists below retain the original planned sequence.

## Global Constraints

- Preserve existing keys, defaults, command behavior, and saved values. Thumbnail choices remain 3, 5, 15, and 0 seconds.
- Automatic tries agy then claude. Explicit selection never changes providers. Snapshot selection when a job starts.
- Preserve process isolation, context input, relevant known words, review output, and footer-free summary.md.
- Use fake system dependencies, isolated defaults, temporary meeting folders, and build/task-verification. No private transcripts, models, real recordings, or calendar operations.
- Stay in this worktree. No extra worktrees, terminals, subagents from workers, installs, live debug-app launch, push, merge, PR, or issue closure.
- You are not alone. Do not revert others. Use apply_patch, never Python. Do not add synchronized source entries to project.pbxproj.
- Show command output directly. Use the parent's temporary directory for scratch. Never add a commit co-author.

## Review Focus

- Preference changes during a suspended transcription must not change its summary provider. Task 1 covers this.
- Explicit tool launch, exit, timeout, empty-output and missing-executable failures must never run the other tool. Task 1 covers these.
- Reopening Settings must preserve stored values and reuse the window. Task 2 covers this.
- Folder cancel, custom paths, and known-word path following must keep existing semantics. Task 2 covers these.
- Closing Settings with another ordinary window open must preserve activation; test-host changes must have no real effects. Task 2 covers these.

### Task 1: Summary-tool policy and job snapshots

**Files:** Settings.swift, MeetingSummarizer.swift, MeetingProcessor.swift, MeetingNotesController.swift, AppDelegate.swift, and focused tests in KuKaTests.

**Interfaces:**
- Produce SummaryTool: String, CaseIterable, Sendable with automatic, antigravity = "agy", claude = "claude". Expose readable title and candidates.
- Produce Settings.summaryTool; missing or unknown key reads automatic without writing.
- Summarizer.summarize(transcript:knownWords:tool:) takes a value, default automatic for existing callers.
- MeetingProcessor.process(_:tool:progress:) and updateNotes(_:tool:) take values, default automatic. Keep tool before progress so trailing closures work.
- MeetingNotesController accepts summaryTool: () -> SummaryTool with automatic default. Read once when dequeuing a job, before await. AppDelegate supplies Settings.summaryTool.

- [ ] Add failing tests for default/persistence/unknown value and candidate order. Names and raw values above are fixed.
- [ ] Run focused SettingsTests and MeetingSummarizerTests and record the expected red result.
- [ ] Implement the enum, persistence and candidate loop. Preserve CLI arguments/PATH/timeout and existing failure detail. Run green.
- [ ] Add failing tests showing explicit agy and claude never fall back for missing executable, launch failure, nonzero exit, timeout, and empty output. Preserve successful review parsing and context with selected tools.
- [ ] Run red, implement minimal changes, run green.
- [ ] Add failing queue/processor tests with a suspended transcriber or runner: current job keeps old choice, next job reads new choice, Retry and Update Notes read latest at their start. Keep queue identity and paths unchanged.
- [ ] Run red, wire immutable tool through the queue and processor, run green. Preserve summary document footer tests and known-word/context suites.
- [ ] Run relevant suites, self-review, commit only task files, write report with exact red/green evidence. Parent runs full suite after Task 2.

Run: xcodebuild -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS' -derivedDataPath build/task-verification test -only-testing:KuKaTests/<RelevantClass>.

### Task 2: Native Settings and menu migration

**Files:** Create SettingsWindowController.swift and optionally SettingsView.swift. Modify Settings.swift, StatusMenu.swift, KeepAwakeController.swift, KeepAwakePanelView.swift, MeetingNotesController.swift, AppDelegate.swift, and relevant existing windows only for activation coordination. Update related tests, README.md, AGENTS.md, CONTEXT.md, and task verification document.

**Interfaces:**
- Consume SummaryTool and Settings.summaryTool from Task 1.
- Produce one retained SettingsWindowController(settings:..., injected pickers/presentation) with show(), refresh on show, and typed callbacks for tiling, clipboard, display awake, and meetings folder.
- Settings.keepDisplayAwake uses the existing key and true default. Add a setter to meetingContextFile; nil removes the key.
- StatusMenu.onShowSettings replaces menu preference callbacks; Settings… has Command-comma.
- KeepAwakeController accepts the display preference and applies updates without owning defaults. Update all callers/tests; do not leave a legacy checkbox API.
- MeetingNotesController exposes a narrow folder-change refresh; remove its picker/setRoot/menu preference code and migrate callers/tests.

- [ ] Write failing native control/action tests for six migrated preferences, summary selection, optional context file choose/clear/cancel, reopening, and no writes on open. Preserve custom duration and all four standard choices.
- [ ] Run red, implement native grouped scrollable form from the spec, run green. File selection uses native sheets in production and injected pickers in tests. Launch-at-login failures show a useful message and actual state.
- [ ] Write failing menu tests requiring one Settings… entry and no persistent controls, while keeping operational items and Keep Awake duration/off.
- [ ] Run red, remove old UI/handlers and wire callbacks in AppDelegate, run green. Tiling and clipboard effects preserve current semantics. Folder changes refresh counts without moving jobs.
- [ ] Cover shared ordinary-window activation and test-host protections before implementing changes. Test Settings construction/show with isolated defaults/fake login, no real activation/polling/hotkeys/permissions. The app host must use isolated settings and inert effects under tests.
- [ ] Verify accessible names and native key-view order. Produce offscreen native Settings snapshots if feasible without launching the debug app or driving the desktop. Keep that evidence distinct from a live keyboard/VoiceOver check.
- [ ] Update current docs and task-specific verification with inventory, choices, integration slots for #28/#41, tests and remaining real-world checks. Fix stale display-awake default wording.
- [ ] Run relevant suites, self-review, commit task files, and report red/green evidence. No screenshots of real personal data.

## Parent completion

- Review each task independently for spec and quality, with bounded fixes.
- Run full KuKaTests after changes. Review new comments and naming.
- Compare native view evidence to mockup. Leave live keyboard/VoiceOver checks explicit if not performed.
- Run final independent whole-branch review. Deliver commits and test evidence without publishing.
