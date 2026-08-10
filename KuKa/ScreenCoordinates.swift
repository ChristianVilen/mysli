import CoreGraphics

/// The vertical flip shared by every top-left/bottom-left screen coordinate
/// conversion in the app: CG (window server) and AX (Accessibility) both use
/// a top-left global origin; NS (AppKit) uses bottom-left. Kept as a neutral,
/// dependency-free namespace so both `WindowListProvider` and
/// `AccessibilityWindowControl` can call it without depending on each other.
enum ScreenCoordinates {
    static func flipVertical(_ frame: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: frame.origin.x,
            y: primaryScreenHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }
}
