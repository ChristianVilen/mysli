# Motion for the Mysli website

Research, 2026-11-06. This note proposes an interaction. It does not change the website or establish shipped behavior. No prototype or performance measurement ran.

Later on the same date, three interactive prototypes were created. See [Mysli motion studies](../../../design-previews/bowl-lab/README.md) for the options, animation details, and browser checks. The research below predates those prototypes.

The brief is a bowl whose ingredients arrive, respond to input, and open feature details. Keep the page white and charcoal with a lingonberry accent. The existing assets in `Mysli/AppIcon.icon/Assets/` are separate SVG files for the bowl and five ingredients. The proposed feature mapping is crisp for screenshots, flakes for clipboard history, split for tiling, bean for Keep Awake, and berry for meetings.

## 1. SVG can give the bowl depth

**Observed evidence.** Animorio publishes a bowl demo with SVG ingredient groups. Ingredients fall in one at a time, and their shadows move closer as they land. Its page includes the markup and describes the effect. The example uses GSAP and ScrollTrigger. It demonstrates the visual technique, not that those dependencies are necessary. See the [creator's bowl demo and source](https://animorio.com/en/animations/recipe-with-the-ingredients-falling-into-the-bowl-on-scroll/).

**Proposal.** Animate Mysli's existing pieces into a loose arrangement over the bowl. Use translation, rotation, scale, and separate shadow shapes to suggest height. Each ingredient can lift when selected and reveal its feature detail beside the bowl. Keep the five feature names visible so visitors do not need to guess what the food shapes mean.

This is the lowest relative effort of the three rendering options below because the artwork already exists. It still needs motion design and responsive layouts. Reusing the shapes does not mean keeping the brown fills.

## 2. Native animation controls support interruption

**Documented evidence.** The Web Animations API exposes playback state and controls. `reverse()` changes the direction of an existing animation. `cancel()` removes its effects, and `commitStyles()` writes its current styles to the element. These are browser APIs. See [MDN's Animation reference](https://developer.mozilla.org/en-US/docs/Web/API/Animation) and [reverse behavior](https://developer.mozilla.org/en-US/docs/Web/API/Animation/reverse).

Chrome's motion guidance recommends `transform` and `opacity` for animation work that can stay on the compositor. That is guidance about property choice, not a frame-rate guarantee for this artwork. See [Chrome's motion guidance](https://developer.chrome.com/docs/modern-web-guidance/guides/ui-behaviors/motion).

**Proposal.** Use CSS for short hover and focus changes, then the Web Animations API for the bowl assembly and ingredient selection. A second activation should reverse or redirect the current movement immediately. Keep the selected feature in application state, and let motion follow that state. Do not queue every click or require the entrance to finish before controls work.

A fixed sequence of keyframes can suggest a small bounce. True spring motion that preserves velocity after a new target needs additional logic or a motion library. Native reverse controls alone do not provide spring physics.

## 3. Layered depth is a useful middle option

**Documented evidence.** CSS `perspective` projects elements according to depth. `transform-style: preserve-3d` lets descendants occupy a shared 3D space. Some grouping properties, including certain opacity and filter values, flatten that space. See [MDN's perspective reference](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/perspective) and [transform-style reference](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/transform-style).

**Proposal.** If the flat animation needs more depth, place the bowl, ingredients, and shadows on separate HTML layers. Give them small depth differences and a restrained pointer tilt. This is often called 2.5D: flat artwork arranged to suggest depth. Keep the depth container separate from layers that fade or clip. On touch screens, keep the bowl still and use taps to select a feature.

This adds medium relative effort. It needs careful overlap, clipping, pointer handling, and testing at different widths. The ingredients remain flat planes, so a large camera orbit would reveal the construction.

**Documented WebGL tradeoffs.** Three.js explains that continuous rendering consumes power when nothing changes, and shows how to render only after input or other changes. Its responsive guide also explains why display resolution affects GPU work. Canvas drawings do not expose semantic controls like HTML does. See [Three.js on rendering on demand](https://threejs.org/manual/pages/rendering-on-demand.html), [responsive rendering](https://threejs.org/manual/pages/responsive.html), and [MDN on canvas accessibility](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/canvas#accessibility).

**Assessment.** WebGL has the highest relative effort here. It makes sense if the chosen design requires a bowl that turns in space, changing lighting, or ingredients with real volume. It would need additional artwork, rendering behavior, and HTML controls. No evidence gathered here shows that those costs improve this five-feature explanation.

## 4. Make each piece a clear control

**Documented evidence.** W3C's disclosure pattern uses a button to show or hide content. Enter and Space activate it, and `aria-expanded` communicates the state. WCAG's minimum target-size criterion is 24 by 24 CSS pixels, with defined exceptions. Larger targets help touch use. See [the disclosure pattern](https://www.w3.org/WAI/ARIA/apg/patterns/disclosure/) and [target-size guidance](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html).

**Proposal.** Use native buttons with feature names, visible focus, and generous hit areas around each ingredient. A click, tap, Enter, or Space opens an inline detail panel. Hover and focus can preview a small lift, but opening must work without hover. The same labeled feature controls can form a list below the bowl on narrow screens. Avoid making visitors drag ingredients to learn about Mysli.

Keeping details inline also avoids the focus management needed for a modal dialog. The bowl is an additional way to explore the content. The feature names and details remain usable if scripts fail or motion is off.

## 5. Concentrate movement in the bowl

**Documented evidence.** `prefers-reduced-motion` exposes the user's preference to remove, reduce, or replace nonessential motion. Large scaling and panning can cause discomfort. See [MDN's reduced-motion reference](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/@media/prefers-reduced-motion).

W3C requires a pause, stop, or hide mechanism for automatically starting movement that lasts more than five seconds and appears alongside other content, unless essential. See [Pause, Stop, Hide](https://www.w3.org/WAI/WCAG22/Understanding/pause-stop-hide.html).

**Proposal.** Let the ingredients arrive once, then settle. Keep the white background still, with a faint static lingonberry glow if needed. Use brief movement after deliberate input rather than an endless drift behind the text. With reduced motion, show the assembled bowl immediately, remove tilt and bounce, and change feature details without spatial movement. If a persistent moving background is chosen later, give visitors a visible pause control.

## Visual references

- [Animorio's ingredient bowl](https://animorio.com/en/animations/recipe-with-the-ingredients-falling-into-the-bowl-on-scroll/) is the closest reference for assembly. Its creator describes a top-down SVG, falling ingredients, closing shadows, and a small settling movement. The live demo was opened in Chrome. Its food palette is not proposed for Mysli.
- [Jeffrey Liu's Quaker Oats project](https://www.jeffkliu.com/projects/advertising/quaker-oats) describes three food layers falling past a bowl before an interactive product gallery. For Mysli, a short ingredient entrance could lead into feature selection. This is a proposal based on the creator's case study, not a live interaction check of that ad.
- [The Magic Bottle](https://magic.estudionk.com/) makes one object the focus of exploration, including removing its cap and shaking it. The [creator's case study](https://www.nk.studio/work/magic-bottle) explains the object-led approach. Mysli could borrow that invitation to play while keeping its installation link and tool descriptions immediately available.

## Recommended scope

Start with SVG artwork in HTML, CSS feedback, and native animation controls. Use one entrance, five selectable ingredients, and one inline detail area. Consider layered depth only after reviewing that version. Treat WebGL as a separate art-direction choice.

Before implementation is called complete, check rapid selection changes, keyboard-only use, touch targets, narrow layouts, zoom, reduced motion, and a page with scripts disabled. Test motion on real Safari and a lower-power mobile device. This research does not establish performance, browser correctness, or accessibility of an implementation.
