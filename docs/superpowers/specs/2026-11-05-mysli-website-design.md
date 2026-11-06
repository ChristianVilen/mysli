# Mysli website redesign

The user chose Product showcase on 2026-11-05 after comparing two interactive mockups. The user rejected the brown theme. The website uses neutral white and charcoal with the lingonberry accent. This replaces the website palette proposed in the November 4 rebrand design.

## Purpose and scope

Explain Mysli as a menu bar app with five tools and give a visitor a clear path to installation. Keep the existing Astro site, Tailwind setup, GitHub Pages deployment, and `/mysli/` base path.

The headline is "A daily mix of Mac tools." The description is "Screenshots, clipboard history, window tiling, Keep Awake and private meeting notes, in one menu bar app."

## Chosen approach

Product showcase uses a left-aligned introduction beside a menu illustration, followed by five tool descriptions, an honest comparison, installation, and help. The illustration uses the existing bowl artwork and readable shortcut symbols. It is an illustration, not evidence of a real recording.

The alternative, Tool playground, put an interactive tool picker in the hero. It made individual features easier to try, but added interaction and maintenance. The user chose the quieter showcase. This change removes the old capture demo instead of adding another playground.

## Appearance

Use the approved mockup's native system typography, restrained borders, and generous space. Light and dark appearances follow the visitor's preference.

| Role | Light | Dark |
|---|---|---|
| Page | `#F8F8FA` | `#141416` |
| Panel | `#FFFFFF` | `#222226` |
| Secondary fill | `#EDEDF1` | `#1C1C20` |
| Border | `#DCDCE3` | `#39393F` |
| Text | `#202024` | `#F4F4F6` |
| Secondary text | `#60606C` | `#B5B5C0` |
| Accent | `#B4233C` | `#E5566B` |

Keep the bowl artwork's original colors. The site backgrounds, text, panels, and borders have no brown tint. Use explicit UTF-8 metadata and encoding-safe shortcut markup. Pause and Stop use shapes rather than font characters.

## Page content

- Navigation has Mysli, The tools, GitHub, and Get Mysli.
- The hero has the headline, all five tools in the description, the menu illustration, installation and tools links, and the macOS 26 requirement.
- Features has one block each for Screenshots, Clipboard history, Window tiling, Keep Awake, and Meeting notes. Each explains a useful action and the relevant shortcut or entry point.
- "One app instead of five" explains the tool categories Mysli covers and its limits. Avoid unsupported competitor claims, prices, or feature counts.
- Installation retains Homebrew and release-download choices. First-launch help explains the unsigned app and the three-step onboarding. Required permissions depend on the chosen tools and calendar reminders.
- Help corrects the old shortcut, tool-switch, Keep screen on, and permissions guidance. The footer has the name explanation and repository links.

Meeting text needs a clear privacy explanation: transcription runs on the Mac; the transcript and typed notes go to the chosen summary provider. The page must not imply that summaries run locally or that note screenshots go to the provider.

## Interaction and verification

Use native links and disclosure elements. Keep command-copy buttons with clear success and failure feedback. Do not capture pointer drags across the hero. Navigation and reading work without JavaScript.

Verify the production build at desktop and phone widths, in light and dark appearances. Check shortcuts, keyboard focus, disclosure controls, command copying, reduced motion, image paths under `/mysli/`, and release links. Capture before and after views with matching settings. This work does not require macOS app tests or changes to the installed app.
