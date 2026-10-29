import XCTest
@testable import KuKa

final class SettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var loginItem: FakeLoginItem!
    private var sut: Settings!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SettingsTests")!
        defaults.removePersistentDomain(forName: "SettingsTests")
        loginItem = FakeLoginItem()
        sut = Settings(defaults: defaults, loginItem: loginItem)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "SettingsTests")
        super.tearDown()
    }

    func testThumbnailDurationDefaultsToFiveAndRoundTrips() {
        XCTAssertEqual(sut.thumbnailDuration, 5.0)
        sut.thumbnailDuration = 15
        XCTAssertEqual(sut.thumbnailDuration, 15)
        XCTAssertEqual(Settings(defaults: defaults, loginItem: loginItem).thumbnailDuration, 15)
    }

    func testWindowTilingDefaultsToTrueAndRoundTrips() {
        XCTAssertTrue(sut.windowTilingEnabled)
        sut.windowTilingEnabled = false
        XCTAssertFalse(sut.windowTilingEnabled)
        XCTAssertFalse(Settings(defaults: defaults, loginItem: loginItem).windowTilingEnabled)
    }

    func testClipboardHistoryEnabledDefaultsToTrue() {
        XCTAssertTrue(sut.clipboardHistoryEnabled)
    }

    func testClipboardHistoryEnabledPersists() {
        sut.clipboardHistoryEnabled = false
        XCTAssertFalse(sut.clipboardHistoryEnabled)
        XCTAssertFalse(Settings(defaults: defaults, loginItem: loginItem).clipboardHistoryEnabled)
    }

    func testMeetingsFolderDefaultsToMeetingsInTheHomeFolder() {
        XCTAssertEqual(sut.meetingsFolder.path, NSHomeDirectory() + "/Meetings")
    }

    func testMeetingsFolderReadsThePathSetWithDefaultsWrite() {
        defaults.set("/Users/test/work/notes", forKey: "meetingsFolder")
        XCTAssertEqual(sut.meetingsFolder.path, "/Users/test/work/notes")

        defaults.set("~/Notes", forKey: "meetingsFolder")
        XCTAssertEqual(sut.meetingsFolder.path, NSHomeDirectory() + "/Notes")
    }

    func testKnownWordsFileDefaultsToKnownWordsMdInTheMeetingsFolderAndFollowsIt() {
        XCTAssertEqual(sut.knownWordsFile.path, NSHomeDirectory() + "/Meetings/known-words.md")

        defaults.set("~/Notes", forKey: "meetingsFolder")
        XCTAssertEqual(sut.knownWordsFile.path, NSHomeDirectory() + "/Notes/known-words.md")
    }

    func testKnownWordsFileReadsThePathSetWithDefaultsWrite() {
        defaults.set("/Users/test/maps/terms.md", forKey: "knownWordsFile")
        XCTAssertEqual(sut.knownWordsFile.path, "/Users/test/maps/terms.md")

        defaults.set("~/maps/terms.md", forKey: "knownWordsFile")
        XCTAssertEqual(sut.knownWordsFile.path, NSHomeDirectory() + "/maps/terms.md")
    }

    func testMeetingLocaleDefaultsToUSEnglishAndReadsTheTagSetWithDefaultsWrite() {
        XCTAssertEqual(sut.meetingLocale.identifier(.bcp47), "en-US")

        defaults.set("de-DE", forKey: "meetingLocale")
        XCTAssertEqual(sut.meetingLocale.identifier(.bcp47), "de-DE")
    }

    func testMeetingControlsTopRightDefaultsToNilAndRoundTrips() {
        XCTAssertNil(sut.meetingControlsTopRight)

        sut.meetingControlsTopRight = CGPoint(x: 1200.5, y: 840)

        XCTAssertEqual(Settings(defaults: defaults, loginItem: loginItem).meetingControlsTopRight,
                       CGPoint(x: 1200.5, y: 840))
    }

    func testMeetingControlsTopRightSetToNilForgetsThePosition() {
        sut.meetingControlsTopRight = CGPoint(x: 10, y: 20)

        sut.meetingControlsTopRight = nil

        XCTAssertNil(defaults.object(forKey: "meetingControlsTopRight"))
        XCTAssertNil(sut.meetingControlsTopRight)
    }

    func testMeetingTranscriptHeightDefaultsTo280AndRoundTrips() {
        XCTAssertEqual(sut.meetingTranscriptHeight, 280)

        sut.meetingTranscriptHeight = 360

        XCTAssertEqual(Settings(defaults: defaults, loginItem: loginItem).meetingTranscriptHeight, 360)
    }

    func testLaunchAtLoginReflectsAndDrivesTheLoginItem() {
        XCTAssertFalse(sut.launchAtLogin)

        sut.setLaunchAtLogin(true)

        XCTAssertEqual(loginItem.setCalls, [true])
        XCTAssertTrue(sut.launchAtLogin)
    }

    func testSetLaunchAtLoginSwallowsRegistrationFailure() {
        loginItem.errorToThrow = NSError(domain: "test", code: 1)

        sut.setLaunchAtLogin(true)

        XCTAssertTrue(loginItem.setCalls.isEmpty)
        XCTAssertFalse(sut.launchAtLogin)
    }
}
