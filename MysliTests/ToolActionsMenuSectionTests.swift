import XCTest
@testable import Mysli

@MainActor
final class ToolActionsMenuSectionTests: XCTestCase {
    private var screenshotsOn = true
    private var clipboardOn = true
    private var tilingOn = true
    private var menu: NSMenu!
    private var sut: ToolActionsMenuSection!

    override func setUp() {
        sut = ToolActionsMenuSection(screenshotsOn: { [unowned self] in screenshotsOn },
                                     clipboardOn: { [unowned self] in clipboardOn },
                                     tilingOn: { [unowned self] in tilingOn })
        menu = NSMenu()
        sut.buildMenuSection(into: menu)
    }

    private func item(_ title: String) throws -> NSMenuItem {
        try XCTUnwrap(menu.items.first { $0.title == title && $0.view == nil }, "no \(title)")
    }

    private func click(_ item: NSMenuItem) {
        _ = (item.target as? NSObject)?.perform(item.action, with: item)
    }

    func testGroupsFollowTheToolOrderAndEachEndsWithASeparator() {
        let headers = menu.items.compactMap { ($0.view as? ToolMenuHeaderView)?.tool }
        XCTAssertEqual(headers, [.screenshots, .clipboard, .windows])
        XCTAssertEqual(menu.items.map { $0.isSeparatorItem ? "-" : $0.title }, [
            "Screenshots", "Capture Area", "Capture Screen", "-",
            "Clipboard", "Show Clipboard History", "-",
            "Windows", "Window Tiling", "-"
        ])
    }

    func testEachActionCallsItsTool() throws {
        var calls: [String] = []
        sut.onCaptureArea = { calls.append("area") }
        sut.onCaptureScreen = { calls.append("screen") }
        sut.onShowClipboardHistory = { calls.append("clipboard") }
        for title in ["Capture Area", "Capture Screen", "Show Clipboard History"] { click(try item(title)) }
        XCTAssertEqual(calls, ["area", "screen", "clipboard"])
    }

    func testOpeningTheMenuShowsTheCurrentSwitches() throws {
        sut.menuWillOpen()
        XCTAssertEqual(try item("Capture Area").keyEquivalent, "4")
        XCTAssertTrue(sut.validateMenuItem(try item("Show Clipboard History")))
        XCTAssertEqual(try item("Window Tiling").state, .on)

        screenshotsOn = false
        clipboardOn = false
        tilingOn = false
        sut.menuWillOpen()
        XCTAssertEqual(try item("Capture Area").keyEquivalent, "", "macOS owns the shortcut now")
        XCTAssertNotNil(try item("Capture Area").action, "capture from the menu still works")
        XCTAssertFalse(sut.validateMenuItem(try item("Show Clipboard History")))
        XCTAssertEqual(try item("Window Tiling").state, .off)
    }

    func testWindowTilingAsksForTheOppositeOfTheCurrentChoice() throws {
        var asked: [Bool] = []
        sut.onToolChanged = { tool, enabled in
            XCTAssertEqual(tool, .windows)
            asked.append(enabled)
        }
        click(try item("Window Tiling"))
        tilingOn = false
        click(try item("Window Tiling"))
        XCTAssertEqual(asked, [false, true])
    }

    func testDisabledToolsHideTheirWholeGroupAndReturnWhenEnabled() {
        screenshotsOn = false
        clipboardOn = false
        tilingOn = false
        sut.menuWillOpen()
        XCTAssertTrue(menu.items.allSatisfy(\.isHidden))

        clipboardOn = true
        sut.menuWillOpen()
        XCTAssertEqual(menu.items.filter { !$0.isHidden }.map { $0.isSeparatorItem ? "-" : $0.title },
                       ["Clipboard", "Show Clipboard History", "-"])
    }
}
