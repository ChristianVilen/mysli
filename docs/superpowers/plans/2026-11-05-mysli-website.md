# Mysli website implementation plan

> **For agentic workers:** Use `superpowers:executing-plans` for implementation in this session, or `superpowers:subagent-driven-development` if the user chooses delegation. Track each completed step below.

**Goal:** Replace the screenshot-focused website with the approved Product showcase for all five Mysli tools.

**Architecture:** Keep the current static Astro page and focused section components. Share brand artwork and site tokens. Keep JavaScript limited to command-copy feedback.

**Tech stack:** Existing Astro, Tailwind CSS, TypeScript, pnpm, and GitHub Pages.

**Spec:** [Mysli website redesign](../specs/2026-11-05-mysli-website-design.md).

**Status:** Implemented locally on 2026-11-06. The user chose the current checkout instead of a worktree. [Verification results and remaining checks](../verification/2026-11-06-mysli-website.md) are recorded separately. Nothing is committed or published.

## Global constraints

- Keep the `/mysli/` base path and existing hosting workflow.
- Use the neutral palette in the spec. Keep lingonberry as the accent.
- Include all five tools and require macOS 26 or later.
- Do not imply that AI summaries stay on the Mac.
- Work in the existing checkout, as the user directed on 2026-11-06.
- Add no dependencies or automated tests unless a specific need or the user's test decision requires them.
- Do not push or deploy as part of local implementation.

## Review focus

- At 320px, navigation, shortcuts, commands, and tables remain readable without page overflow.
- Dark appearance keeps neutral surfaces and readable text and buttons.
- Assets load with the production `/mysli/` base path.
- Keyboard use reaches links, copy buttons, and help disclosures in page order.
- Copy feedback distinguishes a successful clipboard write from denied access.

## Task 1: Build the showcase

**Files:** `site/src/components/{Nav,Hero,Features,Comparison,Footer}.astro`, `site/src/styles/global.css`, `site/tokens.css`, `site/src/layouts/Layout.astro`, `site/src/pages/index.astro`, new brand artwork under `site/public/`.

**Interfaces:** The page keeps the `#top`, `#tools`, and `#install` anchors. Assets use Astro's configured base path. Existing Swift icon layers provide the artwork.

- [x] Install the locked site dependencies in the current checkout.
- [x] Save the unchanged site from `HEAD` and build that baseline.
- [ ] Capture matching desktop and phone baselines. This remains unchecked.
- [x] Replace the Cobalt palette and typography with the approved neutral design. Keep one authoritative token definition and update or remove the redundant token export.
- [x] Add the bowl artwork and the menu illustration. Use numeric entities for shortcut symbols and shapes for recording controls.
- [x] Replace the old feature table with five tool blocks and the comparison with honest tool limits.
- [x] Update navigation, footer, title, and description. Remove the old screenshot workflow section from the page and delete its unused component.
- [x] Run the site build. Check the built asset paths and content under `/mysli/`.

## Task 2: Finish installation and help

**Files:** `site/src/components/Install.astro`, `site/src/components/Troubleshooting.astro`, `site/src/scripts/animations.ts`, `site/src/layouts/Layout.astro`, `site/src/styles/global.css`.

**Interfaces:** Command buttons keep `data-copy` with the exact command string. Native `details` and `summary` own help disclosure behavior.

- [x] Update installation and first-launch text for onboarding and tool-dependent permissions. Retain the current Homebrew commands and release URL.
- [x] Correct help for Carbon shortcuts, screenshot conflicts, tool switches in Settings, and Keep screen on.
- [x] Remove the obsolete capture demo, its styles, and unused assets. Rename the remaining interaction script for its command-copy responsibility and update the layout import.
- [x] Preserve copy success and failure feedback. TDD was offered but not selected. No test code was added.
- [x] Run `pnpm run check`, `pnpm run lint`, and `pnpm run build` in `site/`. Fix findings caused by this change.

## Task 3: Verify and hand over

**Files:** A short verification record under `docs/superpowers/verification/`, with captures kept in one task-owned directory until review.

- [x] Inspect the production preview in Chrome's desktop window and at 768px, 390px, and 320px.
- [ ] Verify exact 1440px and 736px views. Custom viewport input was unreliable.
- [x] Inspect light and dark appearances and enable reduced-motion emulation.
- [x] Check successful command copying, the skip link and its keyboard focus, a help disclosure, and the installation anchor.
- [ ] Check clipboard denial, every control by keyboard, VoiceOver, and external release navigation.
- [x] Obtain an independent source review and fix the asset-path finding.
- [ ] Inspect matching before and after captures.
- [x] Record completed checks and checks that could not run. Mark this plan implemented locally, keeping publication separate from implementation.
- [x] Present the local preview. Keep pushing and publishing outside this local implementation.
