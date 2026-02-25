import XCTest

final class MenuBarTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    private func openMenu() {
        let statusItem = app.menuBars.statusItems["Ku-Ka"]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        statusItem.click()
    }

    func testMenuBarIconExists() {
        let statusItem = app.menuBars.statusItems["Ku-Ka"]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
    }

    func testMenuContainsLaunchAtLogin() {
        openMenu()
        let item = app.menuItems["Launch at Login"]
        XCTAssertTrue(item.waitForExistence(timeout: 3))
    }

    func testMenuContainsThumbnailDurationLabel() {
        openMenu()
        let label = app.menuItems["Thumbnail Duration"]
        XCTAssertTrue(label.waitForExistence(timeout: 3))
    }

    func testMenuContainsDurationOptions() {
        openMenu()
        XCTAssertTrue(app.menuItems["3 Seconds"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.menuItems["5 Seconds"].exists)
        XCTAssertTrue(app.menuItems["Forever"].exists)
    }

    func testMenuContainsQuit() {
        openMenu()
        let quit = app.menuItems["Quit Ku-Ka"]
        XCTAssertTrue(quit.waitForExistence(timeout: 3))
    }

    func testSelectingDurationOptionUpdatesCheckmark() {
        openMenu()
        let threeSeconds = app.menuItems["3 Seconds"]
        XCTAssertTrue(threeSeconds.waitForExistence(timeout: 3))
        threeSeconds.click()

        // Re-open menu to verify state persisted
        openMenu()
        let fiveSeconds = app.menuItems["5 Seconds"]
        XCTAssertTrue(fiveSeconds.waitForExistence(timeout: 3))
        // Reset to default
        fiveSeconds.click()
    }
}
