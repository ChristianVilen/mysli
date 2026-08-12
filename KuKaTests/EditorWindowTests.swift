import XCTest
@testable import KuKa

@MainActor
final class EditorWindowTests: XCTestCase {
    private var store: FakeImageStore!
    private var fileURL: URL!
    private var editor: EditorWindow!

    override func setUp() async throws {
        store = FakeImageStore()
        fileURL = URL(fileURLWithPath: "/tmp/kuka-test/shot.png")
        editor = EditorWindow(image: NSImage(size: NSSize(width: 20, height: 20)), fileURL: fileURL, store: store)
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
        // 80% cap of a synthetic 500x400 visible frame. A square 1000x1000
        // image caps first to w=400, then height wins: h=320, w=320 —
        // content is 320 wide, 320 + 44 toolbar tall.
        let fakeScreens = FakeScreens(
            all: [ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 500, height: 428),
                                 visibleFrame: CGRect(x: 0, y: 0, width: 500, height: 400))],
            mainIndex: 0
        )
        let capped = EditorWindow(image: NSImage(size: NSSize(width: 1000, height: 1000)),
                                  fileURL: fileURL, store: store, screens: fakeScreens)
        defer { capped.close() }

        XCTAssertEqual(capped.contentView?.frame.size, NSSize(width: 320, height: 364))
    }
}
