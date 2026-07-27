import XCTest
@testable import KuKa

final class DrawingViewTests: XCTestCase {
    // Regression: compositing via NSImage.lockFocus re-rendered at the
    // screen's backing scale, saving annotated screenshots at 2x resolution.
    func testCompositeImageKeepsSourcePixelDimensions() {
        let cg = MockScreenCapture.makeImage(width: 100, height: 80)
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        let view = DrawingView(image: image)
        view.frame = NSRect(x: 0, y: 0, width: 50, height: 40)

        let composited = view.compositeImage().cgImage(forProposedRect: nil, context: nil, hints: nil)

        XCTAssertEqual(composited?.width, 100)
        XCTAssertEqual(composited?.height, 80)
    }
}
