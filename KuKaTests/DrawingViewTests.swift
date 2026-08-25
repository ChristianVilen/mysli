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

    func testCropReturnsTheBoxInSourcePixels() {
        // 100x80 px shown at 50x40 pt — 2 px per point. A 20x10 pt box must
        // come back as 40x20 px, cut from the full-resolution composite.
        let cg = MockScreenCapture.makeImage(width: 100, height: 80)
        let view = DrawingView(image: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
        view.frame = NSRect(x: 0, y: 0, width: 50, height: 40)

        let cropped = view.compositeImage(croppedTo: CGRect(x: 10, y: 10, width: 20, height: 10))
            .cgImage(forProposedRect: nil, context: nil, hints: nil)

        XCTAssertEqual(cropped?.width, 40)
        XCTAssertEqual(cropped?.height, 20)
    }

    func testCropKeepsTheSelectedRegionNotItsMirror() {
        let cg = makeTwoToneImage()
        let view = DrawingView(image: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
        view.frame = NSRect(x: 0, y: 0, width: 50, height: 40)

        // The top 10 points of the view: the red half
        let cropped = view.compositeImage(croppedTo: CGRect(x: 0, y: 30, width: 50, height: 10))
            .cgImage(forProposedRect: nil, context: nil, hints: nil)!

        let color = NSBitmapImageRep(cgImage: cropped).colorAt(x: 10, y: 10)!.usingColorSpace(.deviceRGB)!
        XCTAssertEqual(color.redComponent, 1, accuracy: 0.02)
        XCTAssertEqual(color.greenComponent, 0, accuracy: 0.02)
    }

    // MARK: - Private

    /// 100x80 px: top half red, bottom half green. CGContext's y axis points
    /// up, so the fill at y 40...80 is the top of the resulting image.
    private func makeTwoToneImage() -> CGImage {
        let context = CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 40, width: 100, height: 40))
        context.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 40))
        return context.makeImage()!
    }
}
