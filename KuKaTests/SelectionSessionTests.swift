import XCTest
@testable import KuKa

@MainActor
final class FakeOverlayPresenter: OverlayPresenting {
    private(set) var presentCount = 0
    private(set) var dismissCount = 0
    private(set) var lastLayout: [ScreenGeometry] = []
    private(set) var lastKeyScreen: ScreenGeometry?
    private var handler: ((OverlayEvent) -> Void)?

    func present(on layout: [ScreenGeometry], keyScreen: ScreenGeometry?, handler: @escaping (OverlayEvent) -> Void) {
        presentCount += 1
        lastLayout = layout
        lastKeyScreen = keyScreen
        self.handler = handler
    }

    func dismissAll() {
        dismissCount += 1
    }

    func emit(_ event: OverlayEvent) {
        handler?(event)
    }
}

@MainActor
final class SelectionSessionTests: XCTestCase {
    private let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                        visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 875))
    private var presenter: FakeOverlayPresenter!
    private var session: SelectionSession!

    override func setUp() async throws {
        presenter = FakeOverlayPresenter()
        session = SelectionSession(presenter: presenter)
    }

    /// Starts run() in a child task and yields until the presenter has been
    /// asked to present, so the test can emit overlay events.
    private func startRun(mouseLocation: CGPoint) async -> Task<SelectionResult, Never> {
        let task = Task { await self.session.run(on: [self.screen], mouseLocation: mouseLocation) }
        for _ in 0..<100 where presenter.presentCount == 0 { await Task.yield() }
        return task
    }

    private var mouseOnScreen: CGPoint {
        CGPoint(x: screen.frame.midX, y: screen.frame.midY)
    }

    // MARK: - Results

    func testRectSelectionCarriesEmittingScreen() async {
        let task = await startRun(mouseLocation: mouseOnScreen)
        let rect = CGRect(x: 10, y: 20, width: 300, height: 200)
        presenter.emit(.rectSelected(rect, screen: screen))
        let result = await task.value
        XCTAssertEqual(result, .rect(rect, on: screen))
    }

    func testWindowSelectionFallsBackToEmittingScreenWhenNoOverlap() async {
        let task = await startRun(mouseLocation: mouseOnScreen)
        let offscreen = CGRect(x: -99999, y: -99999, width: 10, height: 10)
        let info = WindowInfo(windowID: 42, frame: offscreen, ownerName: "Test", layer: 0)
        presenter.emit(.windowSelected(info, screen: screen))
        let result = await task.value
        XCTAssertEqual(result, .window(42, on: screen))
    }

    func testWindowSelectionPicksScreenContainingWindow() async {
        let task = await startRun(mouseLocation: mouseOnScreen)
        let inside = CGRect(x: screen.frame.midX - 50, y: screen.frame.midY - 50, width: 100, height: 100)
        let info = WindowInfo(windowID: 7, frame: inside, ownerName: "Test", layer: 0)
        presenter.emit(.windowSelected(info, screen: screen))
        let result = await task.value
        XCTAssertEqual(result, .window(7, on: screen))
    }

    // MARK: - Lifecycle

    func testSecondRunWhileActiveResumesCancelled() async {
        let task = await startRun(mouseLocation: mouseOnScreen)
        let second = await session.run(on: [screen], mouseLocation: mouseOnScreen)
        XCTAssertEqual(second, .cancelled)
        XCTAssertEqual(presenter.presentCount, 1, "second run must not present overlays")
        let rect = CGRect(x: 0, y: 0, width: 5, height: 5)
        presenter.emit(.rectSelected(rect, screen: screen))
        let first = await task.value
        XCTAssertEqual(first, .rect(rect, on: screen), "first run must be unaffected by the second call")
    }

    func testTeardownHappensBeforeResultAndOnce() async {
        let task = await startRun(mouseLocation: mouseOnScreen)
        XCTAssertEqual(presenter.dismissCount, 0)
        presenter.emit(.cancelled)
        let result = await task.value
        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(presenter.dismissCount, 1)
    }

    func testDuplicateEventsResumeOnce() async {
        let task = await startRun(mouseLocation: mouseOnScreen)
        let rect = CGRect(x: 1, y: 2, width: 30, height: 40)
        presenter.emit(.rectSelected(rect, screen: screen))
        presenter.emit(.cancelled) // e.g. Esc still arriving from another overlay
        let result = await task.value
        XCTAssertEqual(result, .rect(rect, on: screen))
        XCTAssertEqual(presenter.dismissCount, 1)
    }

    func testEmptyScreenListResumesCancelled() async {
        let result = await session.run(on: [], mouseLocation: .zero)
        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(presenter.presentCount, 0)
    }

    // MARK: - Key-screen election

    func testKeyScreenElectionFollowsMouse() async {
        let task = await startRun(mouseLocation: mouseOnScreen)
        XCTAssertEqual(presenter.lastKeyScreen, screen)
        presenter.emit(.cancelled)
        _ = await task.value
    }

    func testNoKeyScreenWhenMouseOutsideAllScreens() async {
        let task = await startRun(mouseLocation: CGPoint(x: -100000, y: -100000))
        XCTAssertEqual(presenter.presentCount, 1)
        XCTAssertNil(presenter.lastKeyScreen)
        presenter.emit(.cancelled)
        _ = await task.value
    }
}
