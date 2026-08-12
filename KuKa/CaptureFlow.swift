import Cocoa

// Test seams for CaptureFlow's collaborators; the concrete classes
// already match the signatures, so conformances are empty.

@MainActor
protocol SelectionRunning {
    func run(on layout: [ScreenGeometry], mouseLocation: CGPoint) async -> SelectionResult
}

protocol CaptureProviding {
    func capture(rect: CGRect, screenFrame: CGRect, primaryHeight: CGFloat) async -> CaptureResult?
    func captureWindow(windowID: CGWindowID) async -> CaptureResult?
    func captureFullScreen(screenFrame: CGRect, primaryHeight: CGFloat) async -> CaptureResult?
}

@MainActor
protocol ThumbnailPresenting {
    func add(image: NSImage, result: CaptureResult, screen: ScreenGeometry, duration: TimeInterval)
}

extension SelectionSession: SelectionRunning {}
extension CaptureManager: CaptureProviding {}
extension ThumbnailStackManager: ThumbnailPresenting {}

/// Owns the capture pipeline from hotkey to thumbnail: selection (or screen
/// pick for fullscreen), the overlay-settle delay, capture, flash, and
/// handing the result to the thumbnail stack. Works on the screen layout
/// snapshotted at press time; real NSScreens appear only in the adapters.
@MainActor
final class CaptureFlow {
    enum Mode { case interactive, fullScreen }

    private let selection: SelectionRunning
    private let capture: CaptureProviding
    private let thumbnails: ThumbnailPresenting
    private let thumbnailDuration: () -> TimeInterval
    private let flash: (ScreenGeometry) -> Void
    private let settleDelay: TimeInterval

    init(selection: SelectionRunning,
         capture: CaptureProviding,
         thumbnails: ThumbnailPresenting,
         thumbnailDuration: @escaping () -> TimeInterval,
         flash: @escaping (ScreenGeometry) -> Void = { FlashView.flash(on: $0) },
         settleDelay: TimeInterval = 0.05) {
        self.selection = selection
        self.capture = capture
        self.thumbnails = thumbnails
        self.thumbnailDuration = thumbnailDuration
        self.flash = flash
        self.settleDelay = settleDelay
    }

    func start(_ mode: Mode, layout: [ScreenGeometry], mouseLocation: CGPoint) async {
        guard let primaryHeight = layout.first?.frame.height else { return }

        switch mode {
        case .interactive:
            switch await selection.run(on: layout, mouseLocation: mouseLocation) {
            case .rect(let rect, let screen):
                await settleAndShow(screen: screen) {
                    await self.capture.capture(rect: rect, screenFrame: screen.frame, primaryHeight: primaryHeight)
                }
            case .window(let windowID, let screen):
                await settleAndShow(screen: screen) {
                    await self.capture.captureWindow(windowID: windowID)
                }
            case .cancelled:
                break
            }

        case .fullScreen:
            guard let screen = layout.first(where: { $0.frame.contains(mouseLocation) }) ?? layout.first else { return }
            guard let result = await capture.captureFullScreen(screenFrame: screen.frame, primaryHeight: primaryHeight) else { return }
            flash(screen)
            show(result: result, screen: screen)
        }
    }

    private func settleAndShow(screen: ScreenGeometry, _ produce: () async -> CaptureResult?) async {
        // The overlay has just closed; give it a moment to disappear before capturing
        if settleDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(settleDelay * 1_000_000_000))
        }
        guard let result = await produce() else { return }
        show(result: result, screen: screen)
    }

    private func show(result: CaptureResult, screen: ScreenGeometry) {
        thumbnails.add(image: result.image, result: result, screen: screen, duration: thumbnailDuration())
    }
}
