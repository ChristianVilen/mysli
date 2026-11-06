# Mysli website verification

The Product showcase is implemented locally on 2026-11-06. The user asked for changes in the current checkout. Nothing was committed, pushed, or published.

## Living bowl on the homepage

Later on 2026-11-06, the user chose the living bowl prototype. It replaced the menu illustration as the hero, and every section below it took the same paper style. The user approved these decisions:

- All sections stay: tools, privacy, limits, installation, and help.
- Dark appearance is neutral charcoal. The bowl, the pieces, and the tool sheets keep their own colours.
- DM Sans and Caveat are hosted with the site through Astro's fonts feature. Visitors make no requests to Google.
- The hero uses the existing description. "Get Mysli for Mac" goes to the install section.
- The navigation shows the app icon and "Mysli." with the red dot.
- Each tool sheet shows its shortcut and links to its row in the tool list.
- No tests were added. Checks were done in Chrome.

The server renders the bowl and the pieces, so the page works without JavaScript. The script adds the entrance, the lift on hover and focus, the tool sheets, and the demos. The pieces are hidden from assistive technology. The labelled tool buttons under the bowl are the keyboard and screen reader path.

From `site/`, `pnpm run check`, `pnpm run lint`, and `pnpm run build` passed. The build copies two font files into `dist/_astro/fonts/`, and the built page has no Google Fonts address. The site has no TypeScript checker, so the scripts were not type-checked.

Chrome checks, through Claude in Chrome on the dev server:

- At 1397 pixels, dark: the entrance, each piece and each tool button, fast switching, all five demos, Back, "Meet the mix", "Mix again" with a sheet open, and the link from a sheet to its tool row.
- Keyboard: Enter on a tool button opens its sheet and focuses its heading. Tab reaches the demo. Escape closes the sheet, returns focus to the button with a visible ring, and lifts the matching piece.
- Light appearance at 1360 pixels, forced through `color-scheme` in a frame.
- Frames at 1000, 1180, 1360, 820, 768, 390, and 320 pixels. No horizontal overflow. At 900 pixels and less, the sheet opens below the tool buttons and scrolls into view.
- Without JavaScript, in a sandboxed frame: the pieces rest in the bowl, the tool buttons and "Mix again" are hidden, and "Meet the tools" links to the tool list.
- Reduced motion, emulated for the script only: no entrance, selection without the spring, and sheets that only fade. The CSS media query was not emulated.

Not checked: Safari, Firefox, a real phone, VoiceOver, real system reduced motion, slow devices, the GitHub Pages deploy, and command copying after this change. Firefox does not support the scroll-linked handwriting on the section notes, so they appear without it.

## Build and source checks

From `site/`, these commands passed:

- `pnpm run check`
- `pnpm run lint`
- `pnpm run build`

Biome reports two existing configuration notices: its schema version differs from the installed CLI, and `linter.recommended` is deprecated. These notices do not fail either command. Dependencies and the lockfile are unchanged.

The built page has five tool rows. The favicon and both bowl images resolve to `/mysli/mysli.svg`, and that file exists in the build. UTF-8 metadata is present. `git diff --check` passed.

The old site was saved from `HEAD` and built successfully before its temporary files were removed. Matching before-and-after browser captures were not completed.

## Chrome checks

The checks used Chrome's native window and DevTools controls against the production preview at `http://127.0.0.1:4322/mysli/`.

- The desktop view showed the neutral dark palette, bowl artwork, menu illustration, correct shortcut symbols, and recording-control shapes.
- The 390-pixel phone view showed the stacked hero. A touch-specific rule initially kept The tools visible in the navigation. After correcting selector specificity, the 320-pixel view hid that link and kept the remaining navigation within the page.
- At 320 pixels, installation text and all three Homebrew commands wrapped inside their panel. The comparison and meeting privacy text were readable.
- Copy changed its accessible button name to `Copied` with a check mark. Pasting into Chrome's address field, without submitting it, confirmed all three Homebrew commands were on the clipboard.
- The permissions help disclosure expanded and exposed its complete answer.
- The iPad Mini preset, 768 by 1024 pixels, showed the two-column hero in both light and dark appearances.
- Reduced-motion emulation left the page content visible. The site has no entrance animation or capture demo. Smooth scrolling is enabled only without reduced motion.
- Tab reached the visible Skip to content link. Enter followed by Tab moved to Get Mysli for Mac, bypassing navigation.
- Closing DevTools returned Chrome to the full desktop preview and the system's dark appearance.

Chrome's native custom-width field and some offscreen actions were unreliable. The tablet preset supplied the usable intermediate-size check. Exact 736-pixel and 1440-pixel views were not verified.

## Review and limits

An independent source review found one asset-path bug: Astro's base path had no trailing slash, which produced `/myslimysli.svg`. A shared asset export now adds the separator. The built page and Chrome both confirm the fix.

The review also checked all five tools, neutral tokens, unchanged dependencies, native links and disclosures, copy success and failure branches, setup, permissions, and privacy text against the app and README. The copy button's fixed label was removed so its changing feedback is exposed in the accessibility tree.

VoiceOver announcements, clipboard denial, a full keyboard pass through every control, external release-page navigation, and matching before-and-after captures remain unchecked. No automated tests were added. No macOS app, recording, or permission check was part of this website change.

## Implementation decisions

- Work in the existing checkout, as the user requested. The changes remain uncommitted.
- Keep command copying's existing behavior. TDD was offered but not selected, and no documented website coverage requirement requires new test code.
- Use a 768-pixel Chrome preset for the tablet check after custom-width input failed. The exact intermediate-width check remains open.
