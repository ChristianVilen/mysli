# KuKa domain glossary

- **Capture** — producing a screenshot image from a screen region, window, or full screen. Owned by `CaptureManager`; the produced image goes straight to the image store.
- **Image store** — everything that happens to a produced image: disk writes under the Screenshots directory, clipboard, file naming, combining two captures into one, annotation overwrites, deletion, and returning freed memory to the OS. Owned by `ImageStore`.
- **Selection session** — one round of "user picks what to capture": overlays appear on every screen, the user drags a rect, picks a window (Space toggles window mode), or cancels (Esc). Ends with a single `SelectionResult` carrying the screen the capture belongs on. Owned by `SelectionSession`.
- **Capture flow** — the pipeline from hotkey to thumbnail: run a selection session (or pick the screen under the mouse for fullscreen), wait for the overlay to settle, capture, flash on fullscreen, hand the result to the thumbnail stack. Owned by `CaptureFlow`.
- **Thumbnail stack** — the pile of floating capture previews in the screen corner; entries can be edited, combined, deleted, or left to expire. Owned by `ThumbnailStackManager`.
- **Tiling** — moving the focused window to half/maximized/centered positions across screens via hotkeys. Owned by `WindowTilingController`.
- **Keep awake** — a timed session preventing system/display sleep. Owned by `WakeManager` / `KeepAwakeController`.
- **Screen layout** — the displays as plain geometry (`ScreenGeometry`: frame + visible frame), vended by the `Screens` seam so tests can fabricate multi-display layouts. Ambient `NSScreen` reads live only in system adapters. Shared screen math belongs to `ScreenCoordinates`: coordinate flips between NS (bottom-left) and CG/AX (top-left), and the "which screen owns this rect" rule used by tiling and selection.
- **Settings** — the user's preferences (thumbnail duration, window tiling on/off, launch at login), with every key and default defined once. Owned by `Settings`.
- **Status menu** — the menu-bar menu and status-item icon: structure, action handling, checkmark state, and the keep-awake badge. Owned by `StatusMenu`.
