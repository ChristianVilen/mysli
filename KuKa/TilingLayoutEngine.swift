import CoreGraphics

enum TilingAction {
    case leftHalf
    case rightHalf
    case maximize
    case center

    var horizontalDirection: HorizontalDirection? {
        switch self {
        case .leftHalf: return .left
        case .rightHalf: return .right
        case .maximize, .center: return nil
        }
    }
}

enum HorizontalDirection {
    case left
    case right
}

/// All rectangles the engine takes and returns are in the same coordinate
/// space as `NSScreen.visibleFrame` (global, bottom-left origin). Converting
/// to/from Accessibility (top-left origin) coordinates is the caller's job.
struct TilingContext {
    let visibleFrame: CGRect
    /// Visible normal windows on that screen, including the window being tiled.
    let windowCount: Int
    let stageManagerEnabled: Bool
    /// Visible frame of the screen a second half-press hops to: the next
    /// screen in the pressed direction, wrapping. Nil when there is no other
    /// screen or the action has no direction.
    let adjacentVisibleFrame: CGRect?

    /// With a single window Stage Manager hides its strip, so maximize can
    /// use the full visible frame even when Stage Manager is on.
    var stageStripTakesSpace: Bool {
        stageManagerEnabled && windowCount >= 2
    }
}

/// What the caller should do to a window in response to a tiling action.
/// The engine decides; the caller owns saved-frame bookkeeping.
enum TilingResolution: Equatable {
    /// When `savePrevious` is true, the caller should remember the window's
    /// current frame before moving it.
    case move(to: CGRect, savePrevious: Bool)
    case restore(to: CGRect)
}

/// Per-window state kept between a maximize press and whatever press
/// restores it: the frame the window had right before maximizing, and the
/// frame it actually landed on. The two can differ — some apps snap sizes
/// (Terminal's character grid) — so "already maximized" has to be judged
/// against what's really on screen, not the frame Ku-Ka requested.
struct TilingRestoreState {
    let previousFrame: CGRect
    let achievedFrame: CGRect
}

/// Pure, stateless window-tiling layout math and per-action decisions.
struct TilingLayoutEngine {
    /// Fraction of `visibleFrame.width` reserved on the left for the Stage
    /// Manager strip when maximizing with Stage Manager active.
    private static let stageManagerLeftInsetFraction: CGFloat = 0.07
    /// Fraction of `visibleFrame.height` reserved at the top, bottom, and
    /// right (each) when maximizing with Stage Manager active. Height-based
    /// for all three so the gaps come out equal in points.
    private static let stageManagerEdgeInsetFraction: CGFloat = 0.01

    /// Tolerance, in points, for judging whether a window "is" at some
    /// target frame. The Accessibility API doesn't position windows with
    /// exact precision, so an exact equality check would never match.
    private static let frameMatchTolerance: CGFloat = 2.0

    func maximizeFrame(in context: TilingContext) -> CGRect {
        guard context.stageStripTakesSpace else { return context.visibleFrame }
        let leftInset = Self.stageManagerLeftInsetFraction * context.visibleFrame.width
        let edgeInset = Self.stageManagerEdgeInsetFraction * context.visibleFrame.height
        return CGRect(
            x: context.visibleFrame.minX + leftInset,
            y: context.visibleFrame.minY + edgeInset,
            width: context.visibleFrame.width - leftInset - edgeInset,
            height: context.visibleFrame.height - 2 * edgeInset
        )
    }

    /// Nil means do nothing (center on an already maximize-sized window).
    ///
    /// The hop check runs against the ideal half target: an app that snaps
    /// its size by more than the tolerance (Terminal) never hops, just gets
    /// the half re-applied. Maximize is judged against
    /// `restoreState.achievedFrame` instead; see `TilingRestoreState`.
    func resolve(
        action: TilingAction,
        currentFrame: CGRect,
        restoreState: TilingRestoreState?,
        context: TilingContext
    ) -> TilingResolution? {
        switch action {
        case .leftHalf:
            return resolveHalf(.left, currentFrame: currentFrame, context: context)
        case .rightHalf:
            return resolveHalf(.right, currentFrame: currentFrame, context: context)
        case .maximize:
            if let restoreState, Self.isWithinTolerance(currentFrame, restoreState.achievedFrame) {
                return .restore(to: restoreState.previousFrame)
            }
            return .move(to: maximizeFrame(in: context), savePrevious: true)
        case .center:
            if Self.isWithinTolerance(currentFrame.size, maximizeFrame(in: context).size) {
                return nil
            }
            let centered = CGRect(
                x: context.visibleFrame.midX - currentFrame.width / 2,
                y: context.visibleFrame.midY - currentFrame.height / 2,
                width: currentFrame.width,
                height: currentFrame.height
            )
            return .move(to: centered, savePrevious: false)
        }
    }

    private func resolveHalf(_ direction: HorizontalDirection, currentFrame: CGRect, context: TilingContext) -> TilingResolution {
        let target = Self.halfFrame(direction, of: context.visibleFrame)
        if let adjacent = context.adjacentVisibleFrame, Self.isWithinTolerance(currentFrame, target) {
            return .move(to: Self.halfFrame(direction, of: adjacent), savePrevious: false)
        }
        return .move(to: target, savePrevious: false)
    }

    static func halfFrame(_ direction: HorizontalDirection, of visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: direction == .left ? visibleFrame.minX : visibleFrame.midX,
            y: visibleFrame.minY,
            width: visibleFrame.width / 2,
            height: visibleFrame.height
        )
    }

    private static func isWithinTolerance(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= frameMatchTolerance
            && abs(lhs.origin.y - rhs.origin.y) <= frameMatchTolerance
            && isWithinTolerance(lhs.size, rhs.size)
    }

    private static func isWithinTolerance(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) <= frameMatchTolerance
            && abs(lhs.height - rhs.height) <= frameMatchTolerance
    }
}
