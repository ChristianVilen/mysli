import XCTest
@testable import KuKa

@MainActor
final class EditorWindowTests: XCTestCase {
    private var store: FakeImageStore!
    private var fileURL: URL!
    private var editor: EditorWindow!

    /// 1000x800 visible: the 80% cap (800x640) stays above the editor's
    /// minimum content width, so the cap test and the minimum-width test
    /// don't mask each other.
    private let screens = FakeScreens(
        all: [ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 828),
                             visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))],
        mainIndex: 0
    )

    override func setUp() async throws {
        store = FakeImageStore()
        fileURL = URL(fileURLWithPath: "/tmp/kuka-test/shot.png")
        editor = EditorWindow(image: NSImage(size: NSSize(width: 20, height: 20)), fileURL: fileURL, store: store, screens: screens)
    }

    override func tearDown() {
        editor?.close()
        editor = nil
        super.tearDown()
    }

    func testDoneSavesAnnotatedImageToItsOwnURL() {
        editor.doneTapped()

        XCTAssertEqual(store.annotatedCalls.count, 1)
        XCTAssertEqual(store.annotatedCalls[0].url, fileURL)
        XCTAssertTrue(store.deletedURLs.isEmpty)
    }

    func testDeleteRemovesItsOwnFile() {
        editor.deleteTapped()

        XCTAssertEqual(store.deletedURLs, [fileURL])
        XCTAssertTrue(store.annotatedCalls.isEmpty)
    }

    func testWindowSizeIsCappedByInjectedScreenVisibleFrame() {
        // 80% cap of a 1000x800 visible frame is 800x640. A square 1000x1000
        // image caps first to w=800, then height wins: h=640, w=640 —
        // content is 640 wide, 640 + 44 toolbar tall.
        let capped = EditorWindow(image: NSImage(size: NSSize(width: 1000, height: 1000)),
                                  fileURL: fileURL, store: store, screens: screens)
        defer { capped.close() }

        XCTAssertEqual(capped.contentView?.frame.size, NSSize(width: 640, height: 684))
    }

    func testNarrowImageStillGetsTheMinimumToolbarWidth() {
        let narrow = EditorWindow(image: NSImage(size: NSSize(width: 100, height: 100)),
                                  fileURL: fileURL, store: store, screens: screens)
        defer { narrow.close() }

        XCTAssertEqual(narrow.contentView?.frame.size, NSSize(width: 460, height: 144))
    }

    func testDoneSavesTheCroppedImage() {
        // 200x100 px shown at 200x100 pt (well under the cap), so view points
        // equal pixels: a 100x50 pt box must save a 100x50 px image.
        let cg = MockScreenCapture.makeImage(width: 200, height: 100)
        let image = NSImage(cgImage: cg, size: NSSize(width: 200, height: 100))
        let cropping = EditorWindow(image: image, fileURL: fileURL, store: store, screens: screens)
        defer { cropping.close() }

        cropping.cropRect = CGRect(x: 0, y: 0, width: 100, height: 50)
        cropping.doneTapped()

        let saved = store.annotatedCalls[0].image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        XCTAssertEqual(saved?.width, 100)
        XCTAssertEqual(saved?.height, 50)
    }
}
