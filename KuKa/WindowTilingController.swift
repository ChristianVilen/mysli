import Cocoa

/// Ties the tiling feature together: reads the focused window, picks its
/// screen, asks `TilingLayoutEngine` what to do, and carries that out
/// through `WindowControlling`. Owns the one piece of state the engine is
/// kept free of: the map of pre-maximize frames. Entries for closed windows
/// are never cleaned up — accepted for v1; a stale entry is mostly harmless
/// but keeps its `AXUIElement` alive.
@MainActor
final class WindowTilingController {
    private let windowControl: WindowControlling
    private let stageManager: StageManagerDetecting
    private let windowList: WindowListProvider
    private let engine: TilingLayoutEngine
    private let screens: Screens

    private var savedFrames: [WindowHandle: TilingRestoreState] = [:]

    init(
        windowControl: WindowControlling = AccessibilityWindowControl(),
        stageManager: StageManagerDetecting = StageManagerDetector(),
        windowList: WindowListProvider = CGWindowListProvider(),
        engine: TilingLayoutEngine = TilingLayoutEngine(),
        screens: Screens = SystemScreens()
    ) {
        self.windowControl = windowControl
        self.stageManager = stageManager
        self.windowList = windowList
        self.engine = engine
        self.screens = screens
    }

    func tile(_ action: TilingAction) {
        guard let focused = windowControl.focusedWindow() else { return }
        let screens = self.screens.all
        guard let screenIndex = targetScreenIndex(for: focused.frame, screens: screens) else { return }
        let screen = screens[screenIndex]

        let context = TilingContext(
            visibleFrame: screen.visibleFrame,
            windowCount: TilingScreenRules.windowCount(on: screen.frame, windows: windowList.windowsOnScreen()),
            stageManagerEnabled: stageManager.isStageManagerEnabled,
            adjacentVisibleFrame: adjacentVisibleFrame(for: action, screenIndex: screenIndex, screens: screens)
        )

        let handle = focused.handle
        guard let resolution = engine.resolve(
            action: action,
            currentFrame: focused.frame,
            restoreState: savedFrames[handle],
            context: context
        ) else { return }

        switch resolution {
        case .move(let target, let savePrevious):
            let previousFrame = focused.frame
            let achievedFrame = windowControl.setFrame(target, of: handle)
            // Only record state when the move actually landed; otherwise a
            // later restore could snap the window to a frame it never left.
            if savePrevious, let achievedFrame {
                savedFrames[handle] = TilingRestoreState(previousFrame: previousFrame, achievedFrame: achievedFrame)
            }
        case .restore(let saved):
            // Only drop the saved entry once the restore actually landed, so
            // a failed restore can be retried instead of starting over as a
            // fresh maximize.
            guard windowControl.setFrame(saved, of: handle) != nil else { return }
            savedFrames.removeValue(forKey: handle)
        }
    }

    /// Index (into `screens`) of the screen `windowFrame` overlaps the most,
    /// with main-screen and first-screen fallbacks. Nil only when there are
    /// no screens.
    private func targetScreenIndex(for windowFrame: CGRect, screens: [ScreenGeometry]) -> Int? {
        if let index = ScreenCoordinates.bestScreenIndex(for: windowFrame, screenFrames: screens.map(\.frame)) {
            return index
        }
        if let mainIndex = self.screens.mainIndex, screens.indices.contains(mainIndex) {
            return mainIndex
        }
        return screens.isEmpty ? nil : 0
    }

    /// Visible frame of the screen a second half-press should hop to, or nil
    /// for actions without a direction and when there's no other screen.
    private func adjacentVisibleFrame(for action: TilingAction, screenIndex: Int, screens: [ScreenGeometry]) -> CGRect? {
        guard let direction = action.horizontalDirection else { return nil }
        guard let index = TilingScreenRules.adjacentScreenIndex(
            of: screenIndex,
            direction: direction,
            screenFrames: screens.map(\.frame)
        ) else { return nil }
        return screens[index].visibleFrame
    }
}
