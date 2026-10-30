# Liquid Settings and Instructions

The user chose **B, Liquid**, from the interactive comparison. This design adds an Instructions page and gives Settings the glass, color, and depth of that mockup.

## Approaches

**A, Frosted** used a soft glass sidebar and an opaque content area. It offered a quiet layout with less background color.

**B, Liquid** used a floating glass sidebar, colored feature icons, and translucent preference groups. The user selected B for its stronger glass treatment.

## Window and materials

Keep one ordinary AppKit window with native title-bar controls. Use system typography and native macOS glass. The browser mockup establishes the layout and visual direction, but does not define exact native material rendering.

The proposed starting size is 760 by 700 points. A sidebar about 170 points wide contains the Ku-Ka icon, **Settings**, and **Instructions**. Content scrolls separately from navigation. The window can resize without cutting off controls or text.

The sidebar has rounded corners, a light edge, and a glass selection background. Preference groups use a quieter translucent background so labels remain readable. Small blue, violet, and warm orange icons distinguish the groups. Use system colors for text, controls, and selection.

Support light and dark appearance. Reduce Transparency uses solid backgrounds. Increase Contrast strengthens separation. Reduce Motion removes movement between pages. Keyboard focus and VoiceOver names remain available.

## Settings

Keep the three existing groups and all eight preferences:

- General: launch at login, window tiling, clipboard history, and keep display awake.
- Screenshots: thumbnail duration.
- Meeting notes: meetings folder, summary tool, and background file.

Use native switches for Boolean preferences, pop-up controls for choices, and native file sheets. Keep immediate saves and the existing runtime callbacks. Preserve full paths in accessible values and tooltips, custom thumbnail durations, and launch-at-login errors.

Keep the explanation that the whole background file goes to the summary provider. Automatic can send it to both providers. Clear removes the preference and keeps the file.

## Instructions

Start with a short screenshot example and a shortcut list. Show modifier keys as keycaps and provide readable accessibility labels.

Add expandable guides for screenshots and annotation, combining screenshots, window tiling, clipboard history, Keep Awake, meeting notes, and permissions and shortcut setup. Use the current implementation as the source for behavior and shortcut labels.

Instructions stay inside the window and work offline. The page contains guidance only. Changing pages does not change preferences or start app features. Opening Settings from the menu or Command-comma shows the Settings page.

## Scope and verification

Keep the current Settings owner, persistence, activation handling, and isolated preview host. This change adds presentation and navigation, not new preferences or capture and recording behavior.

Run the existing relevant tests. Inspect native Settings and Instructions in both appearances, with long paths, smaller window sizes, keyboard navigation, and accessibility display settings. Browser screenshots alone do not establish that native glass or layout works.

TDD has been offered for navigation through `SettingsWindowController`. Add test code only if the user accepts or documented repository coverage requirements require it.

The user approved the visual direction, native layout, interaction details, and subagent-driven implementation.
