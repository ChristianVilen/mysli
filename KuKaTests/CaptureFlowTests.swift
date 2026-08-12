import XCTest
@testable import KuKa

@MainActor
final class FakeSelection: SelectionRunning {
    var result: SelectionResult = .cancelled
    private(set) var runCount = 0

    func run(on layout: [ScreenGeometry], mouseLocation: CGPoint) async -> SelectionResult {
        runCount += 1
        return result
    }
}

@MainActor
final class FakeCapture: CaptureProviding {
    var result: CaptureResult?
    private(set) var calls: [String] = []

    func capture(rect: CGRect, screenFrame: CGRect, primaryHeight: CGFloat) async -> CaptureResult? {
        calls.append("rect")
        return result
    }

    func captureWindow(windowID: CGWindowID) async -> CaptureResult? {
        calls.append("window:\(windowID)")
        return result
    }

    func captureFullScreen(screenFrame: CGRect, primaryHeight: CGFloat) async -> CaptureResult? {
        calls.append("fullscreen")
        return result
    }
}

@MainActor
final class FakeThumbnails: ThumbnailPresenting {
    private(set) var added: [(screen: ScreenGeometry, duration: TimeInterval)] = []

    func add(image: NSImage, result: CaptureResult, screen: ScreenGeometry, duration: TimeInterval) {
        added.append((screen, duration))
    }
}

@MainActor
final class CaptureFlowTests: XCTestCase {
    private let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                        visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 875))
    private var selection: FakeSelection!
    private var capture: FakeCapture!
    private var thumbnails: FakeThumbnails!
    private var flashedScreens: [ScreenGeometry] = []
    private var flow: CaptureFlow!

    override func setUp() async throws {
        selection = FakeSelection()
        capture = FakeCapture()
        capture.result = CaptureResult(image: NSImage(), fileURL: URL(fileURLWithPath: "/tmp/kuka-test.png"))
        thumbnails = FakeThumbnails()
        flashedScreens = []
        flow = CaptureFlow(
            selection: selection,
            capture: capture,
            thumbnails: thumbnails,
            thumbnailDuration: { 5.0 },
            flash: { self.flashedScreens.append($0) },
            settleDelay: 0
        )
    }

    private var mouseOnScreen: CGPoint {
        CGPoint(x: screen.frame.midX, y: screen.frame.midY)
    }

    // MARK: - Interactive

    func testRectSelectionCapturesRectAndShowsThumbnailOnItsScreen() async {
        selection.result = .rect(CGRect(x: 1, y: 2, width: 300, height: 200), on: screen)
        await flow.start(.interactive, layout: [screen], mouseLocation: mouseOnScreen)
        XCTAssertEqual(capture.calls, ["rect"])
        XCTAssertEqual(thumbnails.added.count, 1)
        XCTAssertEqual(thumbnails.added.first?.screen, screen)
        XCTAssertTrue(flashedScreens.isEmpty, "interactive capture must not flash")
    }

    func testWindowSelectionCapturesThatWindow() async {
        selection.result = .window(42, on: screen)
        await flow.start(.interactive, layout: [screen], mouseLocation: mouseOnScreen)
        XCTAssertEqual(capture.calls, ["window:42"])
        XCTAssertEqual(thumbnails.added.count, 1)
        XCTAssertEqual(thumbnails.added.first?.screen, screen)
        XCTAssertTrue(flashedScreens.isEmpty, "interactive capture must not flash")
    }

    func testCancelledSelectionCapturesNothing() async {
        selection.result = .cancelled
        await flow.start(.interactive, layout: [screen], mouseLocation: mouseOnScreen)
        XCTAssertEqual(selection.runCount, 1)
        XCTAssertTrue(capture.calls.isEmpty)
        XCTAssertTrue(thumbnails.added.isEmpty)
    }

    func testFailedCaptureShowsNoThumbnail() async {
        selection.result = .rect(CGRect(x: 0, y: 0, width: 10, height: 10), on: screen)
        capture.result = nil
        await flow.start(.interactive, layout: [screen], mouseLocation: mouseOnScreen)
        XCTAssertEqual(capture.calls, ["rect"])
        XCTAssertTrue(thumbnails.added.isEmpty)
    }

    // MARK: - Fullscreen

    func testFullScreenCapturesScreenUnderMouseAndFlashes() async {
        await flow.start(.fullScreen, layout: [screen], mouseLocation: mouseOnScreen)
        XCTAssertEqual(capture.calls, ["fullscreen"])
        XCTAssertEqual(flashedScreens, [screen])
        XCTAssertEqual(thumbnails.added.count, 1)
        XCTAssertEqual(thumbnails.added.first?.screen, screen)
        XCTAssertEqual(selection.runCount, 0, "fullscreen must not run a selection session")
    }

    func testFullScreenFallsBackToFirstScreenWhenMouseIsNowhere() async {
        await flow.start(.fullScreen, layout: [screen], mouseLocation: CGPoint(x: -100000, y: -100000))
        XCTAssertEqual(capture.calls, ["fullscreen"])
        XCTAssertEqual(thumbnails.added.first?.screen, screen)
    }

    func testFullScreenWithNoScreensCapturesNothing() async {
        await flow.start(.fullScreen, layout: [], mouseLocation: .zero)
        XCTAssertTrue(capture.calls.isEmpty)
        XCTAssertTrue(flashedScreens.isEmpty)
        XCTAssertTrue(thumbnails.added.isEmpty)
    }

    func testFullScreenFailedCaptureNeitherFlashesNorShowsThumbnail() async {
        capture.result = nil
        await flow.start(.fullScreen, layout: [screen], mouseLocation: mouseOnScreen)
        XCTAssertTrue(flashedScreens.isEmpty)
        XCTAssertTrue(thumbnails.added.isEmpty)
    }

    // MARK: - Duration

    func testThumbnailDurationComesFromInjectedClosure() async {
        flow = CaptureFlow(
            selection: selection,
            capture: capture,
            thumbnails: thumbnails,
            thumbnailDuration: { 3.25 },
            flash: { _ in },
            settleDelay: 0
        )
        selection.result = .rect(CGRect(x: 0, y: 0, width: 10, height: 10), on: screen)
        await flow.start(.interactive, layout: [screen], mouseLocation: mouseOnScreen)
        XCTAssertEqual(thumbnails.added.first?.duration, 3.25)
    }
}
