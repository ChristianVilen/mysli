import XCTest
@testable import KuKa

final class CropBoxTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 100, height: 80)
    private let existing = CGRect(x: 10, y: 10, width: 50, height: 30)

    /// One full mouse gesture: press at `from`, drag to `to`, release.
    private func gesture(_ box: inout CropBox, from: CGPoint, to: CGPoint) {
        box.beginDrag(at: from)
        box.drag(to: to)
        box.endDrag()
    }

    // MARK: - Drawing

    func testDragOnEmptyAreaDrawsABox() {
        var box = CropBox(bounds: bounds)
        gesture(&box, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 40))
        XCTAssertEqual(box.rect, CGRect(x: 10, y: 10, width: 50, height: 30))
    }

    func testDrawingStopsAtTheBounds() {
        var box = CropBox(bounds: bounds)
        gesture(&box, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 200, y: 200))
        XCTAssertEqual(box.rect, CGRect(x: 10, y: 10, width: 90, height: 70))
    }

    func testDrawingStopsAtBoundsWithAnOffsetOrigin() {
        var box = CropBox(bounds: CGRect(x: 20, y: 20, width: 100, height: 80))
        gesture(&box, from: CGPoint(x: 30, y: 30), to: CGPoint(x: 0, y: 0))
        XCTAssertEqual(box.rect, CGRect(x: 20, y: 20, width: 10, height: 10))
    }

    // MARK: - Moving

    func testDragInsideTheBoxMovesIt() {
        var box = CropBox(bounds: bounds, rect: existing)
        gesture(&box, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 30, y: 25))
        XCTAssertEqual(box.rect, CGRect(x: 20, y: 15, width: 50, height: 30))
    }

    func testMovingStopsAtTheBoundsEdge() {
        var box = CropBox(bounds: bounds, rect: existing)
        gesture(&box, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 90, y: 20))
        XCTAssertEqual(box.rect, CGRect(x: 50, y: 10, width: 50, height: 30))
    }

    // MARK: - Resizing

    func testDragOnACornerHandleResizesBothSides() {
        var box = CropBox(bounds: bounds, rect: existing)
        gesture(&box, from: CGPoint(x: 60, y: 40), to: CGPoint(x: 70, y: 50))
        XCTAssertEqual(box.rect, CGRect(x: 10, y: 10, width: 60, height: 40))
    }

    func testDragOnAnEdgeHandleResizesOneSide() {
        var box = CropBox(bounds: bounds, rect: existing)
        gesture(&box, from: CGPoint(x: 35, y: 40), to: CGPoint(x: 35, y: 60))
        XCTAssertEqual(box.rect, CGRect(x: 10, y: 10, width: 50, height: 50))
    }

    func testActionIsResizeNearAHandleMoveInsideAndDrawOutside() {
        let box = CropBox(bounds: bounds, rect: existing)
        XCTAssertEqual(box.action(at: CGPoint(x: 64, y: 44)), .resize(.topRight))
        XCTAssertEqual(box.action(at: CGPoint(x: 30, y: 20)), .move)
        XCTAssertEqual(box.action(at: CGPoint(x: 90, y: 70)), .draw)
    }

    func testDraggingAHandlePastTheOppositeSideFlipsTheBox() {
        var box = CropBox(bounds: bounds, rect: existing)
        gesture(&box, from: CGPoint(x: 60, y: 25), to: CGPoint(x: 0, y: 25))
        XCTAssertEqual(box.rect, CGRect(x: 0, y: 10, width: 10, height: 30))
    }

    func testOnAThinBoxTheNearerSideWins() {
        let thin = CropBox(bounds: bounds, rect: CGRect(x: 10, y: 10, width: 10, height: 30))
        XCTAssertEqual(thin.action(at: CGPoint(x: 18, y: 25)), .resize(.right))
        XCTAssertEqual(thin.action(at: CGPoint(x: 12, y: 25)), .resize(.left))
    }

    // MARK: - Clearing

    func testClickOutsideTheBoxRemovesIt() {
        var box = CropBox(bounds: bounds, rect: existing)
        gesture(&box, from: CGPoint(x: 90, y: 70), to: CGPoint(x: 90, y: 70))
        XCTAssertNil(box.rect)
    }

    func testATinyDragLeavesNoBox() {
        var box = CropBox(bounds: bounds)
        gesture(&box, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10.5, y: 10.5))
        XCTAssertNil(box.rect)
    }

    // MARK: - Init

    func testABoxGivenAtInitIsCutToTheBounds() {
        let box = CropBox(bounds: bounds, rect: CGRect(x: 50, y: 50, width: 100, height: 100))
        XCTAssertEqual(box.rect, CGRect(x: 50, y: 50, width: 50, height: 30))
        XCTAssertNil(CropBox(bounds: bounds, rect: CGRect(x: 200, y: 200, width: 10, height: 10)).rect)
    }
}
