# Liquid Settings implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Give Ku-Ka a native glass Settings window with an offline Instructions page.

**Architecture:** Keep `SettingsWindowController` as the preference and presentation owner. A `SettingsPage` enum selects Settings or Instructions. Native AppKit views provide the glass sidebar, preference groups, and expandable guides. The isolated preview host and existing injected actions stay in place.

**Tech Stack:** Swift, AppKit, native macOS glass, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-30-settings-liquid-design.md`

## Global constraints

- Keep one ordinary AppKit window with native title-bar controls. Use system typography and native macOS glass.
- The proposed starting size is 760 by 700 points. A sidebar about 170 points wide contains the Ku-Ka icon, Settings, and Instructions. Content scrolls separately from navigation. The window can resize without cutting off controls or text.
- Support light and dark appearance. Reduce Transparency uses solid backgrounds. Increase Contrast strengthens separation. Reduce Motion removes movement between pages. Keyboard focus and VoiceOver names remain available.
- Keep the three existing groups and all eight preferences. Use native switches for Boolean preferences, pop-up controls for choices, and native file sheets. Keep immediate saves and the existing runtime callbacks.
- Preserve full paths in accessible values and tooltips, custom thumbnail durations, and launch-at-login errors.
- Keep the explanation that the whole background file goes to the summary provider. Automatic can send it to both providers. Clear removes the preference and keeps the file.
- Instructions stay inside the window and work offline. The page contains guidance only. Changing pages does not change preferences or start app features. Opening Settings from the menu or Command-comma shows the Settings page.
- Keep the current Settings owner, persistence, activation handling, and isolated preview host. This change adds presentation and navigation, not new preferences or capture and recording behavior.
- Do not add test code. TDD was offered, and the user did not opt in. Adjust obsolete existing assertions only when the approved layout requires it.
- Do not launch production Ku-Ka, read real meeting contents, download models, push, create a PR, or merge.
- Use apply_patch for edits. Do not use Python. Keep scratch files under the current task directory supplied in the brief or this plan's SDD workspace.

## Review focus

The following checks use existing tests and a temporary native renderer rather than new test code.

- Long synthetic folder and background paths must fit at the minimum size and retain their complete accessible values and tooltips.
- Switching pages and reopening Settings must preserve preferences, restore the Settings page on show, and keep a useful native key-view chain.
- Light, dark, Reduce Transparency, and Increase Contrast must keep labels readable and separate the navigation and preference groups.
- Expanded Instructions must scroll independently of navigation, keep readable modifier-key labels, and describe current implementation behavior.
- Native switches must retain the existing public control seams, persistence, typed callbacks, login failure feedback, and native file sheets.

---

### Task 1: Build and verify the cohesive Settings window

**Files:**
- Modify: `KuKa/SettingsWindowController.swift`, owning page selection, all existing preference controls and callbacks, and presentation.
- Create if useful: `KuKa/SettingsWindowViews.swift`, owning shared glass, group, sidebar, and row presentation.
- Create: `KuKa/SettingsInstructionsView.swift`, owning static offline instructions, shortcut keycaps, and native disclosure controls.
- Modify only if required: `KuKa/SettingsPreviewAppDelegate.swift` and obsolete layout assertions in `KuKaTests/SettingsWindowControllerTests.swift`.
- Modify: `AGENTS.md`, updating Settings structure and responsibilities.
- Create: `docs/superpowers/verification/2026-10-30-settings-liquid.md` and evidence under `docs/superpowers/evidence/settings-liquid/`.

**Interfaces:**
- Consumes: existing `Settings`, `SettingsWindowController.Picker`, injected `present`, `OrdinaryWindowActivation`, typed preference callbacks, and all existing controller control properties.
- Produces: `enum SettingsPage: CaseIterable { case settings, instructions }`, one selected page owned by the controller, a native sidebar selection action, and unchanged preference actions.
- Produces: the same `SettingsWindowController.show()` entry point, which selects Settings before presentation.
- Instructions view takes no production services and performs no feature actions. Use native disclosure controls with collapsed guides by default.

- [ ] **Step 1: Read the approved spec, the visual reference B / `.bold`, existing controller and tests, and prior native verification document.** Inspect existing glass in `ClipboardPanel.swift` and `MeetingControlsPanel.swift`. Use current implementation for shortcut and guide wording. Do not inspect real meetings.
- [ ] **Step 2: Implement the window, pages, and native controls.** Use the page enum as the only page state. Keep one retained ordinary window. Build a floating rounded sidebar and colored preference group icons with native glass. Lay out adaptive rows so the content can resize and scroll. Do not add decorative window gradients or browser-style glass substitutes. Keep all existing preference actions and file picker implementations. Keep controls accessible and preserve full path values.
- [ ] **Step 3: Add the offline Instructions page.** Include the short screenshot example, shortcut list with keycaps, and expandable guides for screenshots and annotation, combining screenshots, window tiling, clipboard history, Keep Awake, meeting notes, and permissions and shortcut setup. Make keyboard focus work for navigation, guides, and preference controls. Page changes have no animation, which satisfies Reduce Motion.
- [ ] **Step 4: Run focused existing tests.** Use `xcodebuild -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS' -derivedDataPath build/task-verification test -only-testing:KuKaTests/AppLaunchModeTests -only-testing:KuKaTests/SettingsWindowControllerTests -only-testing:KuKaTests/SettingsTests -only-testing:KuKaTests/StatusMenuTests`. Expect zero failures. Change obsolete geometry assertions only when the new approved resizable layout invalidates them, and report each change.
- [ ] **Step 5: Verify the real native views with a temporary standalone Swift renderer outside KuKa and KuKaTests.** Read `docs/superpowers/verification/2026-10-29-settings-window.md` first. Use synthetic paths, inert login and sheets, and isolated preferences. Render Settings and Instructions in light and dark at the starting size and a smaller size. Inspect images. Exercise navigation and disclosure controls through native target actions, assert no settings changes on navigation, verify reopening selects Settings, and inspect accessibility and key-view order. Exercise accessibility display settings through a narrow view-level input if OS changes are unavailable. Record the exact method and limitations. Do not claim live glass from opaque offscreen images.
- [ ] **Step 6: Run the existing full KuKaTests suite once.** Use the same project, scheme, destination, and DerivedData. Do not enable optional real model or audio fixtures. Expect zero failures and report skipped checks and existing warnings.
- [ ] **Step 7: Update AGENTS.md and verification evidence.** Record controls, navigation, exact commands and results, native evidence paths, and remaining desktop material or VoiceOver limitations. Keep the old baseline image. Follow repository file-system synchronized source rules and do not change the Xcode project manually.
- [ ] **Step 8: Review the diff, run deslop, and commit the complete verified task.** Do not add a co-author. Return a report with commit IDs, commands, exact test counts, native checks, screenshots inspected, changes to existing tests, and remaining limits. Do not dispatch reviewers. The controller dispatches independent review afterward.
