# Clipboard History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** `docs/superpowers/specs/2026-08-25-clipboard-history-design.md` — read it first. The spec holds every decision; this plan only sequences the work.

**Goal:** A Raycast-style clipboard history. Ku-Ka records copies (text with rich flavors, images), `Shift+Cmd+C` opens a Liquid Glass panel, typing filters, arrows move, Enter pastes into the previously focused app. Formatted text gets a "without / with formatting" chooser, "without" first. In-memory only, capped, toggleable from the status menu.

**Architecture:** Pure `ClipboardHistory` model over `ClipboardItem` values. `PasteboardReading`/`PasteboardWriting` seam over `NSPasteboard.general`, `KeystrokeSending` seam for the synthetic `Cmd+V`. One `@MainActor` `ClipboardHistoryController` owns poll timer, history, and panel. `ClipboardPanel` (on `FloatingPanel`) is view-only and reports through closures. Hotkey routed through the existing `HotkeyManager` enum, gated like tiling. Raises the app minimum to macOS 26 for `NSGlassEffectView`.

**Tech Stack:** Swift 5 mode, AppKit, CryptoKit (SHA-256), CoreGraphics (`CGEvent` for `Cmd+V`), XCTest.

---

## Critical build note (read before starting)

`KuKa.xcodeproj/project.pbxproj` uses **explicit file references** — files on disk are NOT picked up automatically. Every new `.swift` file MUST be added to the right target or the build fails:

- App code (`ClipboardItem.swift`, `ClipboardHistory.swift`, `ClipboardPasteboard.swift`, `ClipboardHistoryController.swift`, `ClipboardPanel.swift`) → **KuKa** target.
- Tests (`ClipboardHistoryTests.swift`, `ClipboardHistoryControllerTests.swift`) → **KuKaTests** target.

Add via Xcode (*Add Files to "KuKa"…*, check the target) or edit `project.pbxproj` by hand using the `SelectionSession.swift` / `SelectionSessionTests.swift` entries as the template (`PBXBuildFile`, `PBXFileReference`, group child, Sources phase).

**Common commands:**

- Build: `xcodebuild -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS' build`
- All tests: `xcodebuild -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS' test`
- One class: append `-only-testing:KuKaTests/ClipboardHistoryTests`

---

## Task 1: Raise the minimum to macOS 26

No feature code until the project builds against the new floor.

**Files:** `KuKa.xcodeproj/project.pbxproj`, `KuKa/Info.plist`

- [ ] Change all six `MACOSX_DEPLOYMENT_TARGET = 14.0;` entries to `26.0;`.
- [ ] Change `LSMinimumSystemVersion` in `Info.plist` to `26.0`.
- [ ] Build and run all existing tests. Expected: green, possibly new deprecation warnings — note them, do not fix them in this branch.

(Doc and site mentions of "macOS 14" are batched in Task 10; the Homebrew cask `depends_on` lives in the tap repo and changes at release time.)

## Task 2: `ClipboardItem` + `ClipboardHistory` — pure model (TDD)

**Files:** create `KuKa/ClipboardItem.swift`, `KuKa/ClipboardHistory.swift`, `KuKaTests/ClipboardHistoryTests.swift`

Shapes (from the spec):

```swift
enum ClipboardItemKind: Equatable {
    case text(plain: String, rtf: Data?, html: Data?)
    case image(png: Data, pixelSize: CGSize)
}

struct ClipboardItem: Equatable {
    let kind: ClipboardItemKind
    let contentHash: String   // SHA-256 hex of plain-text bytes or PNG bytes
    let copiedAt: Date
    var hasRichFlavors: Bool  // text with rtf or html present
    var byteCost: Int         // image PNG byte count; 0 for text
    var previewLabel: String  // one line of text, or "Image 938×773"
}

struct ClipboardHistory {
    static let maxItems = 100
    static let maxImageBytes = 100_000_000
    static let maxItemBytes = 50_000_000
    private(set) var items: [ClipboardItem]  // newest first
    mutating func add(_ item: ClipboardItem)
    mutating func remove(hash: String)
    mutating func clear()
    func filtered(query: String) -> [ClipboardItem]
}
```

- [ ] **Red:** write `ClipboardHistoryTests` — each test one behavior:
  - `testAddPutsNewestFirst`
  - `testDuplicateHashMovesToTopWithoutGrowing`
  - `testItemCapEvictsOldest` (add 101, oldest gone, count 100)
  - `testImageByteBudgetEvictsOldestUntilUnderBudget`
  - `testItemAboveMaxItemBytesIsRefused`
  - `testFilterMatchesTextContentCaseInsensitive`
  - `testFilterMatchesImageLabel`
  - `testRemoveByHash`, `testClearEmpties`
  - `testHasRichFlavorsOnlyWhenRtfOrHtmlPresent`
- [ ] Add both files to their targets (see build note). Run the class — expected: compile failure, then assertion failures.
- [ ] **Green:** implement the two files. Hash helper on `ClipboardItem` (CryptoKit) so tests and later the pasteboard adapter build items the same way.
- [ ] Run the class, then the full suite.

## Task 3: Pasteboard and keystroke seams

**Files:** create `KuKa/ClipboardPasteboard.swift`; extend `KuKaTests/Mocks.swift`

```swift
protocol PasteboardReading: AnyObject {
    var changeCount: Int { get }
    func readCurrentItem(now: Date) -> ClipboardItem?  // nil: marked, oversized, unsupported
}
protocol PasteboardWriting: AnyObject {
    func write(_ item: ClipboardItem, withFormatting: Bool) -> Int  // change count the write produced, for self-write suppression
}
protocol KeystrokeSending { func sendPasteKeystroke() }
```

- [ ] `SystemPasteboard` implements both pasteboard protocols on `NSPasteboard.general`:
  - Skip when any of `org.nspasteboard.ConcealedType` / `TransientType` / `AutoGeneratedType` is present.
  - Read image first (`.png`, else `.tiff` re-encoded to PNG via `NSBitmapImageRep`), else `.string` plus raw `.rtf` / `.html` data.
  - Refuse payloads over `ClipboardHistory.maxItemBytes`.
  - Write: `clearContents()`, then plain string only, or plain + rtf + html; images always as PNG (+ TIFF under the existing `ImageStore` pixel-cap rule — reuse `defaultClipboardTIFFMaxPixels`).
- [ ] `CGEventKeystrokeSender` implements `KeystrokeSending`: key-down/key-up for `kVK_ANSI_V` (0x09) with `flags = .maskCommand` exactly, posted to `.cghidEventTap`.
- [ ] Add `FakePasteboard` (settable `changeCount`, scripted `readCurrentItem` results, recorded writes) and `FakeKeystrokeSender` (counts calls) to `Mocks.swift`.
- [ ] No unit tests for the system adapters (repo convention). Build must stay green.

## Task 4: `ClipboardHistoryController` (TDD)

**Files:** create `KuKa/ClipboardHistoryController.swift`, `KuKaTests/ClipboardHistoryControllerTests.swift`

`@MainActor` class. Init takes `reader: PasteboardReading`, `writer: PasteboardWriting`, `keystrokes: KeystrokeSending`, defaults to the system types. Production runs a 0.5 s main-queue timer that calls `pollNow()`; tests call `pollNow()` directly — no timer seam needed.

State the panel needs, exposed as read-only + a `onListChanged` closure: visible items (filter applied), selection index, mode (`.list` / `.chooser`).

- [ ] **Red:** `ClipboardHistoryControllerTests`:
  - `testPollWithNewChangeCountAddsItem`
  - `testPollWithSameChangeCountReadsNothing` (fake counts reads)
  - `testPollSkipsWhenReaderReturnsNil` (marked/oversized handled in reader; controller just moves on)
  - `testDisableStopsPollingAndClearsHistory`
  - `testEnableResumesPolling`
  - `testEnterOnPlainTextPastesImmediately` (write called with `withFormatting: false`, keystroke sent, panel-close callback fired)
  - `testEnterOnImagePastesImmediately`
  - `testEnterOnRichTextEntersChooserMode`
  - `testChooserFirstOptionPastesWithoutFormatting`
  - `testChooserSecondOptionPastesWithFormatting`
  - `testEscInChooserReturnsToList`
  - `testScreenshotHashRemovalDropsItem`
  - `testPasteMovesItemToTopPreservingRichFlavors` (paste without formatting moves the item to the top and keeps its RTF/HTML)
  - `testOwnPasteWriteIsNotRecordedByNextPoll` (self-write suppression: the poll right after our own paste re-reads nothing)
- [ ] Add files to targets; run class — red.
- [ ] **Green:** implement. Paste hand-off order: notify panel to close → `writer.write(...)` → send keystroke after a ~50 ms one-shot `Timer` on `RunLoop.main` (`.common` mode) so focus settles back on the target app (same trick as the capture flow's overlay delay).
- [ ] Full suite green.

## Task 5: Hotkey routing (TDD)

**Files:** `KuKa/HotkeyManager.swift`, `KuKaTests/HotkeyManagerTests.swift`

- [ ] **Red:** extend `HotkeyManagerTests`:
  - `testShiftCommandCRoutesToShowClipboardHistoryWhenEnabled` (swallowed)
  - `testShiftCommandCPassesThroughWhenDisabled`
  - `testShiftCommandCWithExtraModifiersPassesThrough` (Ctrl or Option present → not ours)
  - existing combos: unchanged in both states.
- [ ] **Green:** add `case showClipboardHistory` to `HotkeyAction`; add `clipboardHistoryEnabled` flag (mirrors `tilingEnabled`); match key code `0x08` with Shift+Command required, Control/Option absent.
- [ ] Full suite green.

## Task 6: Settings (TDD)

**Files:** `KuKa/Settings.swift`, `KuKaTests/SettingsTests.swift`

- [ ] **Red:** `testClipboardHistoryEnabledDefaultsTrue`, `testClipboardHistoryEnabledPersists` (pattern of the existing `windowTilingEnabled` tests).
- [ ] **Green:** add `clipboardHistoryEnabled` backed by the `"clipboardHistoryEnabled"` key.

## Task 7: `ImageStore` deletion hook (TDD)

**Files:** `KuKa/ImageStore.swift`, `KuKaTests/ImageStoreTests.swift`

- [ ] **Red:**
  - `testStoreRemembersContentHashPerFile`
  - `testDeleteReportsHashOfDeletedFile` (closure fires with the stored hash)
  - `testDeleteOfUnknownURLReportsNothing`
- [ ] **Green:** session-scoped `[URL: String]` map filled in `store(cgImage:fileName:)` and `saveAnnotated` (hash of the PNG bytes it just wrote), `var onDeletedHash: ((String) -> Void)?` called from `delete(at:)`. Reuse `ClipboardItem`'s hash helper so hashes line up with history keys.

## Task 8: `ClipboardPanel` — glass UI (no tests)

**Files:** create `KuKa/ClipboardPanel.swift`

- [ ] Subclass `FloatingPanel`, override `canBecomeKey` → true. Close on `resignKey`.
- [ ] Chrome: `NSGlassEffectView` filling the panel; content stack = search `NSTextField` + `NSTableView` (view-based, single column). Tune corner radius / scrim by eye against a busy wallpaper.
- [ ] Rows: type icon + `previewLabel`; image rows add a small thumbnail decoded on demand (never retain full bitmaps).
- [ ] Chooser mode: swap the table content for the two fixed rows ("Paste without formatting" pre-selected, "Paste with formatting").
- [ ] Key handling: search field stays first responder; intercept Up/Down/Enter/Esc in `control(_:textView:doCommandBySelector:)` and forward to the controller's closures; all other typing edits the filter.
- [ ] Empty state: single "Nothing copied yet" row.
- [ ] Placement: horizontally centered, top third of the screen under the cursor — reuse the `Screens` seam / `ScreenCoordinates` helpers for the geometry.
- [ ] Wire panel ↔ controller closures both ways (list changed → reload; key events → controller).

## Task 9: Menu, AppDelegate wiring

**Files:** `KuKa/StatusMenu.swift`, `KuKaTests/StatusMenuTests.swift`, `KuKa/AppDelegate.swift`

- [ ] `StatusMenu`: "Clipboard History" checkbox next to "Window Tiling" (state from `settings.clipboardHistoryEnabled`, `onClipboardHistoryToggled` closure) + a `⌘⇧C clipboard history` line in the Features section. Extend `StatusMenuTests` following the tiling-toggle tests.
- [ ] `AppDelegate`: own `ClipboardHistoryController`; route `case .showClipboardHistory` in the hotkey switch; set `hotkeyManager.clipboardHistoryEnabled` from settings at startup and from the toggle callback; toggle-off calls `controller.disable()` (stops poll, clears); wire `imageStore.onDeletedHash` → `controller.removeItem(hash:)`.
- [ ] Create the panel, call `bindController()` once (panel half-works without it).
- [ ] Controller's poll only starts when enabled — and note: polling needs no permission, so it starts regardless of the Accessibility/Screen Recording state; only the *hotkey* depends on Accessibility (tap), and paste needs Accessibility too, which the tap already guarantees.
- [ ] Full suite green. Manual smoke (see Task 11 checklist).

## Task 10: Documentation and site

**Files:** `README.md`, `AGENTS.md`, `CONTEXT.md`, `APP_STORE.md`, `site/src/components/Hero.astro`, `site/src/components/Install.astro`

- [ ] README: feature bullet + a "Clipboard History" section (hotkey, chooser, in-memory + caps, toggle, privacy markers); requirements → macOS 26; drop the stale "macOS 14+ for ScreenCaptureKit" note.
- [ ] AGENTS.md: file table + key-classes rows for the five new files, hotkey note (`Shift+Cmd+C`, gating flag), test coverage list, macOS 26 in the three version mentions.
- [ ] AGENTS.md: add an `AppDelegate` key-classes row covering the clipboard-history toggle callback, `ClipboardHistoryController` ownership, and `ClipboardPanel` ownership (added in Task 9).
- [ ] AGENTS.md: update the "Test-Mode Guard" paragraph — `isTesting` now also skips `clipboardHistory.enable()` at startup, not just `setupPermissions()`.
- [ ] AGENTS.md: add CryptoKit to the Frameworks list (flagged in earlier reviews).
- [ ] AGENTS.md: add the clipboard-history test suites to the unit-test coverage list (flagged in earlier reviews).
- [ ] CONTEXT.md: add a **Clipboard history** glossary entry (recorded copies, the panel, the chooser; owned by `ClipboardHistoryController`).
- [ ] CONTEXT.md: Settings glossary entry gains the `clipboardHistoryEnabled` key.
- [ ] Site: both "macOS 14 (Sonoma)" strings → macOS 26 (Tahoe).
- [ ] APP_STORE.md: version line.
- [ ] Check `.github/workflows/release.yml`: confirm `macos-latest` provides Xcode 26; if not, pin (`macos-26`).

## Task 11: Final verification

- [ ] Full test suite green; app builds Release.
- [ ] Manual smoke checklist:
  - Copy text in two apps → both appear, newest first; re-copy the first → moves to top, no duplicate.
  - `Shift+Cmd+C` → panel opens on cursor's screen, first row selected; Enter pastes into the app you came from.
  - Copy from a rich source (browser) → Enter shows chooser, "without" first; both options paste correctly.
  - Type → list filters; Esc → closes; click outside → closes.
  - Copy a password in a password manager → does not appear.
  - Take a screenshot → appears as image row; delete it from the thumbnail → row gone.
  - Toggle Clipboard History off → `Shift+Cmd+C` reaches the frontmost app again (Chrome: Inspect Element); toggle on → works again, history empty.
  - Quit and relaunch → history empty, toggle state remembered.
