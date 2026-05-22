# Deepening Opportunities

Architectural candidates for refactoring Ku-Ka toward deeper modules with better testability and locality.

---

## 1. AppDelegate is a shallow orchestrator of the capture pipeline

**Files**: `AppDelegate.swift`

**Problem**: AppDelegate knows every step of the pipeline by name: create overlays, wire selection callbacks, handle the 50ms delay, dispatch to `CaptureManager`, show thumbnail, wire editor. None of this is hidden — callers (and future maintainers) must read the whole class to understand even one step. Deletion test: delete the orchestration logic from `startCapture()` through `showThumbnail()` — the complexity doesn't concentrate anywhere, it reappears scattered. There is no named module representing "a capture flow." The test surface is zero — AppDelegate is completely untestable.

**Solution**: Extract a `CaptureFlow` module that owns the pipeline from hotkey trigger to thumbnail shown. It takes a `CaptureManager`, `SelectionSession`, and `ThumbnailStackManager` and exposes a single `start()` method. AppDelegate becomes a wiring file only.

**Benefits**: Every step of the pipeline is tested through a single interface. The 50ms delay, overlay dismissal sequencing, mode handling — all become locality in one module. A future "screen recording" flow would reuse the same seam.

---

## 2. The overlay + selection lifecycle has no module

**Files**: `AppDelegate.swift`, `OverlayWindow.swift`, `SelectionView.swift`

**Problem**: AppDelegate manually creates one `OverlayWindow` per screen, wires `onSelection`, `onWindowSelection`, and `onCancel` on each `SelectionView`, and calls `dismissOverlays()`. Both capture modes (selection rect and window pick) are handled with separate callback paths in AppDelegate. The full interface a caller needs includes: which screen created which overlay, how mode-switching propagates, how cancellation works. The `OverlayWindow` module itself is nearly empty — it just holds a `SelectionView` and exists only as a thin wrapper.

**Solution**: A `SelectionSession` module: given an array of `NSScreen`s, it creates the overlay windows internally and calls back with a single `SelectionResult` (either `.rect(CGRect, NSScreen)` or `.window(CGWindowID)`). AppDelegate calls `session.start(on: screens)` and handles one result type. Cancellation is internal.

**Benefits**: The multi-screen lifecycle, mode-toggling, and callback multiplexing disappear behind a small interface. `OverlayWindow` becomes an implementation detail of `SelectionSession`. The seam is real: two callers already exist conceptually (selection mode and window mode), and a future "annotation overlay" flow would use the same seam.

---

## 3. User preferences are ambient state spread across two modules

**Files**: `AppDelegate.swift`, `ThumbnailStackManager.swift`

**Problem**: Thumbnail duration is written by AppDelegate (via menu action) and read by both AppDelegate and `ThumbnailStackManager` directly from `UserDefaults`. `ThumbnailStackManager` reaches across its seam into `UserDefaults` at runtime rather than receiving the duration as a parameter. Launch-at-login state also lives inline in AppDelegate. Callers can't test `ThumbnailStackManager` timer behavior without stubbing `UserDefaults`.

**Solution**: A `Settings` module that centralizes `thumbnailDuration` and `launchAtLogin` as typed properties backed by `UserDefaults`. `ThumbnailStackManager` receives a `duration: TimeInterval` at construction time (or via a typed settings dependency), not via `UserDefaults` reads.

**Benefits**: Timer behavior in `ThumbnailStackManager` becomes testable without `UserDefaults` side effects. The settings change propagation path becomes explicit rather than ambient.

---

## 4. CaptureManager combines image production and annotation persistence

**Files**: `CaptureManager.swift`

**Problem**: `CaptureManager` has a natural core — `capture()`, `captureFullScreen()`, `captureWindow()`, `saveToDisk()`, `copyToClipboard()` — that forms a deep module (three protocols, rich behavior behind a small interface). But `saveCombined()` and `saveAnnotated()` are structurally different: they receive already-produced `NSImage`s and persist them. These methods don't use `ScreenCapturing` at all — they're image-persistence operations grafted onto a capture module. Deletion test: if you deleted `saveCombined()` from `CaptureManager`, its complexity would reappear in AppDelegate — so it's earning its keep somewhere. But its seam is wrong: it sits behind a capture interface rather than a persistence interface.

**Solution**: Extract an `ImageStore` module with `save(image:)`, `saveAnnotated(image:url:)`, `saveCombined(images:)`, `delete(url:)`. `CaptureManager` uses `ImageStore` internally or is split: capture stays in `CaptureManager`, annotation/persistence moves to `ImageStore`.

**Benefits**: The annotation and combine paths get their own test surface without needing `MockScreenCapture`. `CaptureManager`'s interface sharpens to just capture operations.
