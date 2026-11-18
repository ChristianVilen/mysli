# Settings search implementation plan

> Use superpowers:executing-plans to implement this plan in this session.

**Goal:** Find individual settings and help without knowing their page names.

**Architecture:** A native search field above the sidebar replaces its page list with ranked results. Pages register search text with each control or action. The sidebar owns the catalog and displays typed page or result rows. Matcher indices stay inside filtering; selection carries the destination to the window.

**Tech stack:** AppKit and Swift. No new dependencies.

The user delegated the design choices and accepted TDD. Work stays on `feat/settings-search` in the clean current checkout.

## Design choices

Page-name filtering misses individual settings. A separate results page hides the current settings and needs another navigation step. Use sidebar results with a page name beneath each result instead.

- Match all query words, regardless of order, with case and accent folding.
- Rank exact labels before partial labels, aliases, descriptions, and page context. Allow one typing error in words of at least four letters.
- Index fixed UI text and useful aliases. Do not index paths, preference values, clipboard text, or meeting content.
- Typing keeps the current page and text focus. Click or Return opens the chosen result, scrolls it into view, and focuses its control.
- Arrow keys select results. Escape clears the query. Clearing restores all pages and keeps the current page.
- Command-F focuses search through `StatusMenu.applicationMenu()` and the responder chain.
- Keep onboarding unchanged. Show a useful empty state. Use native controls and accessibility labels.

## Review focus

Check unrelated multi-word queries, short words that must not get fuzzy matches, keyboard focus after navigation, hidden permission rows, and the minimum window size.

## Tasks

- [x] Add matcher tests and observe failure. Implement matching and observe success.
- [x] Add navigation integration tests and observe failure. Register destinations and implement the native sidebar search.
- [x] Generate native renders at 760 × 700 and 640 × 420 in light and dark appearances. Check layout and destination visibility.
- [x] Run the full suite and `scripts/check-tests.sh`. Review the diff and update README usage.
- [ ] Complete manual mouse, keyboard, and VoiceOver checks. Computer use is unavailable in this session.

## Verification results

After the approved review fixes, the full suite passed with 1,177 tests passed and 13 opt-in checks skipped. `scripts/check-tests.sh` passed. Search matching, aliases, keyboard commands, destination focus, guide expansion, empty results, clearing, and permission availability have automated coverage. Search does not write preferences.

The independent review found hidden permission results and missing Help button aliases. Both have regression tests and are fixed. Native rendering exposed a table-update crash. The table now keeps its displayed data stable while row styles change and reloads after replacing the data. The render sequence then passed.

Native renders have paint artifacts that also occur in the baseline. They support layout checks, but do not establish live appearance or interaction.

## Verification

Use `xcodebuild -project Mysli.xcodeproj -scheme Mysli -destination 'platform=macOS,arch=arm64' test`, with focused `-only-testing` arguments during TDD. Run `scripts/check-tests.sh` against the final result bundle. Use only `--uitesting` for the native preview.

## Approved review fixes

The user approved all findings from the judo review.

- [x] B1: Register destinations beside rows and standalone actions. Index the keyboard setup instructions. Delete view-tree discovery and the metadata-only `SettingsRow`.
- [x] B2: Move Escape cancellation to the Settings window controller. Verify the native cancel command from the focused result control, search field, and results table.
- [x] S1: Give the sidebar typed destinations and `.page` or `.result` rows. Remove the copied item catalog and integer callbacks between controllers.
- [x] C1: Rename the Teams tile Boolean `item` to `isMenuItem`.
- [x] Run focused regressions, native picture generation, the full suite, and the timing check. Keep manual UI checks separate.

Both behavioral regressions failed before the fixes and passed afterward. Keyboard setup searches reveal the button without opening System Settings. Escape clears search through the current first responder, including the revealed control, search field, and results table. The independent review found no remaining issue in B1, B2, S1, or C1. All 20 native picture variants rendered successfully. Manual interaction and VoiceOver remain unchecked because computer use is unavailable.
