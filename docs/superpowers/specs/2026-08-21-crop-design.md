# Crop in the Editor — Design

**Date:** 2026-08-21
**Status:** Approved
**Branch:** `crop-screenshot`

## Summary

Let the user crop a screenshot after taking it. Cropping lives in the existing editor
window (the window that opens when the user clicks a thumbnail). The user turns on a
**Crop** tool, drags a box over the image, adjusts the box with handles or by moving it,
and presses **Done**. Done saves the cropped image (with any strokes) to the same file
and copies it to the clipboard, exactly as annotation does today.

The user chose this over two alternatives: a drag-only box with no handles (less precise)
and a Preview-style crop that shrinks the window at once (more work: window resize and
stroke remapping).

## Goals

- Crop a capture from the editor, without leaving the app.
- An adjustable crop box: draw it, resize it from any edge or corner, move it.
- Crop and freehand strokes combine into one saved image.
- Output pixels come from the source capture at full resolution. No re-render at the
  screen's backing scale (the bug class `DrawingViewTests` already guards against).
- The crop box geometry is a pure model with unit tests.

## Non-goals

- No crop button on the thumbnail panel. The editor is the "edit after capture" step.
- No aspect-ratio lock, no rotation, no window resize while cropping.
- No undo history for the crop box. The box is removed by a click outside it.
- No keyboard shortcut for the Crop tool.
- No change to the capture pipeline, the thumbnail stack, or the image store API.

## User experience

Editor toolbar, left to right:

```
[ Undo ] [ Crop ]          [ 🗑 ]          [ Done ]
```

- **Crop** is a toggle button. On = crop tool. Off = drawing tool (today's behaviour).
- **Crop tool on:**
  - Drag on the image: draws a new box. The area outside the box is dimmed. A label under
    the box shows the output size in pixels, for example `1200 × 800`.
  - Drag a corner or edge handle: resizes that corner or side. The box cannot leave the
    image. If a handle is dragged past the opposite side, the box flips instead of getting
    a negative size.
  - Drag inside the box: moves it. It stops at the image edge.
  - Click outside the box without dragging: removes the box.
  - Cursor: crosshair over the image, open hand inside the box, resize arrows on the
    left/right and top/bottom edges. The corner handle areas outside the box keep the
    crosshair (AppKit has no public diagonal resize cursor); just inside a corner the
    open hand wins, because inside the box always means move.
- **Crop tool off:**
  - The box stays visible, with the dimming, so the user sees what will be saved. It
    cannot be changed. Strokes can be drawn anywhere, also in the dimmed area.
- **Undo** removes the last stroke in both modes. It does not touch the crop box.
- **Done** flattens the strokes onto the full-resolution image, then cuts out the crop
  box. The result overwrites the same file and goes to the clipboard. Without a box, Done
  works as today.
- **Delete**, the close button and **Escape** are unchanged.
- The editor content is at least 460 points wide so the four toolbar buttons never
  overlap (Undo 12–92, Crop 100–180, trash centred at 190–270, Done 368–448). An image
  narrower than that is centered in the window.

## Architecture

Follows the Ku-Ka pattern: pure logic in a value type with tests, AppKit kept thin in
views, and the window only wiring things together.

### Components

**`CropBox` (pure, testable) — new file `KuKa/CropBox.swift`**

Geometry of an adjustable crop rectangle inside fixed bounds. Points are in the host
view's coordinate space (origin bottom-left, y up), so `top` means the maxY side. No
AppKit import.

```
struct CropBox {
    enum Handle: Equatable {
        case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight
    }
    enum Action: Equatable { case draw, move, resize(Handle) }

    static let handleHitRadius: CGFloat = 8      // points around a handle that still hit it

    let bounds: CGRect                           // the image area
    private(set) var rect: CGRect?               // nil = no crop box

    init(bounds: CGRect, rect: CGRect? = nil)    // a given rect is cut to bounds; no overlap → nil

    func action(at point: CGPoint) -> Action     // what a drag from this point would do
    mutating func beginDrag(at point: CGPoint)
    mutating func drag(to point: CGPoint)
    mutating func endDrag()
}
```

Rules:

- `action(at:)`: a point within `handleHitRadius` of a corner → `.resize(corner)`; within
  the radius of an edge, along that edge → `.resize(edge)`; inside the box → `.move`;
  anywhere else (or no box) → `.draw`. Corners win over edges. On a box thinner than
  twice the radius a point can be within reach of both opposite sides; then the nearer
  side wins, so a thin box can still be resized from either side.
- `beginDrag`: stores the action and its anchor (drag origin, move offset, or the box as
  it was). A `.draw` start drops the existing box at once.
- `drag(to:)`: the point is clamped to `bounds` first. Draw → box from the origin to the
  point. Move → translate by the mouse delta, then push the box back inside `bounds`.
  Resize → the handle's side(s) follow the point; the result is standardized, which is
  what makes the box flip.
- `endDrag`: a box narrower or shorter than 1 point becomes `nil`. This is also how a
  click outside the box clears it.

**`DrawingView` — `KuKa/DrawingView.swift`**

`compositeImage()` becomes `compositeImage(croppedTo rect: CGRect? = nil)`. With a rect it
composites the strokes as today, then cuts the result with `CGImage.cropping(to:)`. The
rect is mapped from view points (origin bottom-left) to image pixels (origin top-left):

```
sx = pixelWidth / bounds.width,   sy = pixelHeight / bounds.height   (already used for strokes)
x = minX · sx,  y = (bounds.height − maxY) · sy,  w = width · sx,  h = height · sy   (rounded)
```

If the mapped rect is empty or the crop fails, the uncropped composite is returned.

**`CropOverlayView` — new file `KuKa/CropOverlayView.swift`**

An `NSView` laid over the `DrawingView` with the same frame. Owns one `CropBox`.

- `var isEditing: Bool` — true: receives mouse events and draws the handles. False:
  `hitTest` returns `nil`, so clicks fall through to the `DrawingView` below; only the
  dimming, border, and label are drawn.
- `var cropRect: CGRect?` — get/set, forwards to the box.
- `init(frame:imagePixelSize:)` — the pixel size feeds the size label.
- Mouse: `mouseDown` → `beginDrag`, `mouseDragged` → `drag`, `mouseUp` → `endDrag`; each
  marks the view for display.
- Drawing: black at 40 % outside the box (even-odd path), 1.5 pt white border, eight 8×8
  white handles with a dark outline while editing, and the size label in output pixels.
  The label's style lives in a small shared `SizeLabel` enum that `SelectionView` uses too,
  and its numbers come from the same `DrawingView.pixelRect(for:in:imagePixelSize:)`
  mapping that Done uses, so the label never disagrees with the saved file.
- Cursor rects are rebuilt when editing toggles, when the box changes, and after a drag.

**`EditorWindow` — `KuKa/EditorWindow.swift`**

- Adds the **Crop** toggle button (`NSButton`, push-on/push-off, title "Crop") after Undo.
- Creates the `CropOverlayView` with the drawing view's frame and adds it above the
  drawing view. The toggle sets `isEditing`.
- Content width is `max(imageWidth, 460)`; the image frame is centered horizontally.
  Toolbar buttons are positioned from the content width.
- `var cropRect: CGRect?` (internal) forwards to the overlay. Tests use it.
- Done → `store.saveAnnotated(image: drawingView.compositeImage(croppedTo: cropRect), to: fileURL)`.

No changes to `ImageStore`, `ThumbnailStackManager`, `CaptureFlow`, or `AppDelegate`.
`saveAnnotated` keeps its name: a crop is one more kind of "annotation overwrite" in the
image store's vocabulary.

## Edge cases

- Drag goes past the image edge → the point is clamped; the box stays inside.
- Handle dragged past the opposite side → the box flips; no negative size.
- Box resized or drawn smaller than 1 point → removed on mouse up.
- Crop tool toggled off while a box exists → box stays, just not editable.
- Done with a box and strokes → strokes outside the box are cut off with the rest.
- Done with a box but no strokes → only the crop is applied.
- Retina: the window is capped at 80 % of the screen, so view points ≠ image pixels is the
  normal case. Strokes and crop use the same scale, so they stay in line.
- Very small image (for example 20×20 test image) → content is still 460 wide; the image
  sits centered.

## Testing

XCTest in `KuKaTests`. TDD (red → green) at these seams, agreed with the user:

- `CropBoxTests` (new):
  - drag on an empty area draws a box; drawing stops at the bounds
  - drag inside the box moves it; moving stops at the bounds edge
  - drag on a corner handle resizes both sides; on an edge handle resizes one side
  - the handle hit area extends `handleHitRadius` outside the box; inside is move;
    far away is draw
  - on a thin box the nearer side wins (10 pt wide box: x = 18 hits right, x = 12 hits left)
  - a rect given at init is cut to the bounds; drawing also stops at bounds with a
    non-zero origin
  - dragging a handle past the opposite side flips the box
  - click outside the box removes it; a tiny drag leaves no box
- `DrawingViewTests` (extend):
  - `compositeImage(croppedTo:)` returns the crop in source pixels (view 50×40,
    image 100×80, box 20×10 pt → 40×20 px)
  - the crop keeps the region the user selected, not its mirror (two-colour image, box
    at the top of the view → the top colour)
- `EditorWindowTests` (extend):
  - Done with a crop rect hands the store an image of the cropped pixel size
  - a narrow image still gets the 460-point minimum content width
  - the existing cap test moves to a larger fake screen so the cap stays above the
    minimum width (1000×800 visible → 640×684 content)

`CropOverlayView` drawing, cursors, and mouse handling are AppKit and are verified by
hand, like the rest of the editor UI.

## Files touched

- `KuKa/CropBox.swift` (new) — pure crop box model.
- `KuKa/CropOverlayView.swift` (new) — the overlay view.
- `KuKa/SizeLabel.swift` (new) — the shared "W × H" label style; `KuKa/SelectionView.swift`
  switches to it (no behaviour change).
- `KuKa/DrawingView.swift` — `compositeImage(croppedTo:)` and the static
  `pixelRect(for:in:imagePixelSize:)` mapping.
- `KuKa/EditorWindow.swift` — Crop toggle, overlay, minimum width, Done with crop.
- `KuKa.xcodeproj/project.pbxproj` — register the two new source files and the new test
  file (the project lists files by hand).
- `KuKaTests/CropBoxTests.swift` (new).
- `KuKaTests/DrawingViewTests.swift`, `KuKaTests/EditorWindowTests.swift` — extended.
- `README.md` — feature bullet, the editor steps under Usage, and the unit-test list.
- `CONTEXT.md` — glossary entries for **Editor** and **Crop box**.
- `site/src/components/{Features,HowItWorks,Comparison}.astro` — the three one-line
  mentions of the editor on the website gain "crop".
