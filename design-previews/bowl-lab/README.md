# Mysli motion studies

Three interactive prototypes, made on 2026-11-06. These are alternatives for review, not changes to the production page.

The user chose the living bowl. It is now the hero of the site in `site/`. The files here stay as a reference, and the site does not use them.

Open the gallery at `/mysli/bowl-lab/` on the local Astro preview. The header switches between options, replays the current option, and opens it separately.

## The living bowl

An introduction built around a large illustrated bowl. Five paper ingredients arrive in sequence. Pencil annotations draw in, and the bowl settles after the arrival. Hover or focus lifts a piece. Click a piece or its tool name to bring it forward and open a paper feature preview.

Try the capture preview, move between tools quickly, and use Back or Escape. The spring keeps its current position and velocity when its destination changes. Keyboard focus moves into the open feature and returns to its trigger on close.

This is the most direct extension of the chosen Product showcase. It has one main interaction and keeps installation visible.

## Mix your own

A pantry, an empty overhead bowl, and a paper receipt. Select ingredients to send them into the bowl, then remove them from the bowl or receipt. Add the whole mix sends all five in. Start fresh returns them to the pantry.

Flights can reverse during movement. Scroll and resize settle them into the current selection. The receipt updates immediately. This is a preview of choosing tools; it changes no Mac settings or installation choices.

This is the most playful option. On phones, the pantry, bowl, and receipt stack vertically, so the full interaction takes more scrolling.

## Five good things

A scroll story with five chapters and a sticky bowl. Each chapter lifts its ingredient out of the mix and develops an illustration of that tool. Chapter buttons offer a direct route through the story. Scrolling remains native.

Try the chapter buttons and scroll in either direction. The bowl becomes a small companion on phones so that chapter text and illustrations remain readable.

This gives each tool the most space. It changes the structure of the page more than the other options.

## Artwork and motion

The shared SVG artwork is original to these studies: a porcelain bowl, a crop-marked crisp, green leaves, a blue split-window piece, a brown coffee bean, and a berry. Irregular contours, pencil marks, paper edges, translucent tape, and separate shadows give them a hand-drawn collage character. The living bowl's resting pieces sit behind its front rim, then lift out when selected.

`art.js` draws the shared pieces. `common.css` defines the neutral paper palette and the DM Sans and Caveat typefaces. Fonts load from Google Fonts, with local fallbacks. The living bowl uses the small native spring in `motion.js`. Other movement uses CSS and the browser's Web Animations API. There are no animation-library or framework dependencies.

Automatic entrances finish and settle. Reduced motion skips the ingredient entrance and spatial transitions. Labels, native buttons, keyboard focus, and feature text remain available.

The [research note](../../docs/superpowers/research/2026-11-06-bowl-motion.md) records the references and tradeoffs. The animation and artwork here were created for Mysli rather than copied from those references.

## Verification

Isolated Chrome checked the three pages at 1440px, 390px, and 320px, including reduced motion. The final browser pass found no page-script errors and no persistent horizontal overflow at those widths.

The checks exercised ingredient selection, the capture preview, rapid keyboard selection, Escape, focus entry and restoration, adding all five tools, clearing the mix, the Meetings scroll chapter, and all three gallery options. Screenshots were inspected during review. The checks found and corrected overlapping ingredient hit areas, narrow grid sizing, a decorative background overflow, a caption collision, hidden-trigger focus, and joined mobile copy.

This is prototype verification. It does not establish Safari behavior, VoiceOver announcements, lower-power device performance, or production readiness. Nothing was published.

## Repeat the preview

After building the site, prepare the prototype files from the repository root:

```sh
node design-previews/bowl-lab/preview.mjs
```

Then start the existing Astro preview from `site/`:

```sh
pnpm run preview --host 127.0.0.1 --port 4323
```

Open `/mysli/bowl-lab/` on the URL Astro reports. If the port is occupied, Astro can choose the next one. A new site build clears the generated copies, so run the preparation command again afterward.
