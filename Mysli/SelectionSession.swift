import Cocoa

/// Result of one selection session: what the user picked, and the screen
/// the capture belongs on.
enum SelectionResult: Equatable {
    case rect(CGRect, on: ScreenGeometry)
    case window(CGWindowID, on: ScreenGeometry)
    case cancelled
}

/// Event emitted by the overlay layer while a session is active.
/// `screen` is the screen whose overlay emitted the event.
enum OverlayEvent {
    case rectSelected(CGRect, screen: ScreenGeometry)
    case windowSelected(WindowInfo, screen: ScreenGeometry)
    case cancelled
}

/// Internal seam: how a session puts selection overlays on screen.
/// The production adapter drives real OverlayWindows; tests drive a fake.
@MainActor
protocol OverlayPresenting {
    func present(on layout: [ScreenGeometry], keyScreen: ScreenGeometry?, handler: @escaping (OverlayEvent) -> Void)
    func dismissAll()
}

/// Owns the overlay + selection lifecycle: one overlay per screen, key-window
/// election on the cursor screen, mode toggling inside the views, teardown.
/// `run` resumes only after the overlays are gone.
@MainActor
final class SelectionSession {
    private let presenter: OverlayPresenting
    private var continuation: CheckedContinuation<SelectionResult, Never>?
    private var isActive = false

    init(presenter: OverlayPresenting = OverlayPresenter(windowListProvider: CGWindowListProvider())) {
        self.presenter = presenter
    }

    func run(on layout: [ScreenGeometry], mouseLocation: CGPoint) async -> SelectionResult {
        guard !isActive, !layout.isEmpty else { return .cancelled }
        isActive = true
        defer { isActive = false }

        let keyScreen = ScreenGeometry.under(mouseLocation, in: layout)

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            presenter.present(on: layout, keyScreen: keyScreen) { [weak self] event in
                self?.handle(event, layout: layout)
            }
        }
    }

    private func handle(_ event: OverlayEvent, layout: [ScreenGeometry]) {
        // Overlays can emit more than one event (e.g. Esc from a second
        // screen while the first is resolving); only the first one counts.
        guard let continuation else { return }
        self.continuation = nil
        presenter.dismissAll()
        continuation.resume(returning: result(for: event, layout: layout))
    }

    private func result(for event: OverlayEvent, layout: [ScreenGeometry]) -> SelectionResult {
        switch event {
        case .rectSelected(let rect, let screen):
            return .rect(rect, on: screen)
        case .windowSelected(let info, let overlayScreen):
            let owner = ScreenCoordinates.bestScreenIndex(for: info.frame, screenFrames: layout.map(\.frame))
                .map { layout[$0] }
            return .window(info.windowID, on: owner ?? overlayScreen)
        case .cancelled:
            return .cancelled
        }
    }
}

/// Production adapter at the OverlayPresenting seam: real OverlayWindows,
/// app activation, cursor teardown. The only place the selection feature
/// touches NSScreen — each layout entry is matched back to its live screen
/// by frame; entries whose screen has vanished since the layout snapshot
/// get no overlay.
@MainActor
final class OverlayPresenter: OverlayPresenting {
    private let windowListProvider: WindowListProvider
    private var overlayWindows: [OverlayWindow] = []

    init(windowListProvider: WindowListProvider) {
        self.windowListProvider = windowListProvider
    }

    func present(on layout: [ScreenGeometry], keyScreen: ScreenGeometry?, handler: @escaping (OverlayEvent) -> Void) {
        // Pushed once per session; dismissAll pops the matching once. The
        // cursor is app-global, so per-overlay pushes would leak stack
        // entries on multi-display layouts.
        NSCursor.crosshair.push()

        let screens = NSScreen.screens
        var keyOverlay: OverlayWindow?

        for geometry in layout {
            guard let screen = screens.first(where: { $0.frame == geometry.frame }) else { continue }
            let overlay = OverlayWindow(screen: screen)
            overlay.selectionView.windowListProvider = windowListProvider
            overlay.selectionView.onSelection = { rect in
                handler(.rectSelected(rect, screen: geometry))
            }
            overlay.selectionView.onWindowSelection = { info in
                handler(.windowSelected(info, screen: geometry))
            }
            overlay.selectionView.onCancel = {
                handler(.cancelled)
            }
            overlayWindows.append(overlay)
            if geometry == keyScreen {
                keyOverlay = overlay
            }
        }

        NSApp.activate(ignoringOtherApps: true)

        for overlay in overlayWindows {
            if overlay === keyOverlay {
                overlay.makeKeyAndOrderFront(nil)
                overlay.makeFirstResponder(overlay.selectionView)
            } else {
                overlay.orderFront(nil)
            }
        }
    }

    func dismissAll() {
        NSCursor.pop()
        for overlay in overlayWindows {
            overlay.close()
        }
        overlayWindows.removeAll()
    }
}
