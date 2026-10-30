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

    func testSummaryToolDefaultsAndUnknownValuesDoNotWriteAndChoicesPersist() {
        XCTAssertEqual(sut.summaryTool, .automatic)
        XCTAssertNil(defaults.object(forKey: "summaryTool"))
        defaults.set("future", forKey: "summaryTool")
        XCTAssertEqual(sut.summaryTool, .automatic)
        XCTAssertEqual(defaults.string(forKey: "summaryTool"), "future")
        for tool in SummaryTool.allCases {
            sut.summaryTool = tool
            XCTAssertEqual(defaults.string(forKey: "summaryTool"), tool.rawValue)
            XCTAssertEqual(Settings(defaults: defaults, loginItem: loginItem).summaryTool, tool)
        }
    }

    func testTeamsSpeakerNamesAreOptInAndPersistWithTheDocumentedKey() {
        XCTAssertFalse(sut.teamsSpeakerNamesEnabled)
        sut.teamsSpeakerNamesEnabled = true
        XCTAssertEqual(defaults.object(forKey: "teamsSpeakerNamesEnabled") as? Bool, true)
        XCTAssertTrue(Settings(defaults: defaults, loginItem: loginItem).teamsSpeakerNamesEnabled)
        sut.teamsSpeakerNamesEnabled = false
        XCTAssertFalse(Settings(defaults: defaults, loginItem: loginItem).teamsSpeakerNamesEnabled)
    }

    func testThumbnailDurationDefaultsToFiveAndRoundTrips() {
        XCTAssertEqual(sut.thumbnailDuration, 5.0)
        sut.thumbnailDuration = 15
        XCTAssertEqual(sut.thumbnailDuration, 15)
        XCTAssertEqual(Settings(defaults: defaults, loginItem: loginItem).thumbnailDuration, 15)
    }

    func testDisplayAwakeKeepsItsTrueDefaultAndExistingKey() {
        XCTAssertTrue(sut.keepDisplayAwake)
        XCTAssertNil(defaults.object(forKey: "keepDisplayAwake"))
        sut.keepDisplayAwake = false
        XCTAssertEqual(defaults.object(forKey: "keepDisplayAwake") as? Bool, false)
        XCTAssertFalse(Settings(defaults: defaults, loginItem: loginItem).keepDisplayAwake)
    }

    func testContextSetterSavesThePathAndNilRemovesTheKey() {
        sut.meetingContextFile = URL(fileURLWithPath: "/Users/example/background.md")
        XCTAssertEqual(defaults.string(forKey: "meetingContextFile"), "/Users/example/background.md")
        sut.meetingContextFile = nil
        XCTAssertNil(defaults.object(forKey: "meetingContextFile"))
    }

    func testMeetingContextHasNoDefaultAndReadsEachNewPath() {
        XCTAssertNil(sut.meetingContextFile)
        defaults.set("", forKey: "meetingContextFile")
        XCTAssertNil(sut.meetingContextFile)
        defaults.set("~/context.md", forKey: "meetingContextFile")
        XCTAssertEqual(sut.meetingContextFile?.path, NSHomeDirectory() + "/context.md")
        defaults.set("/other/context.md", forKey: "meetingContextFile")
        XCTAssertEqual(sut.meetingContextFile?.path, "/other/context.md")
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

    func testChosenMeetingsFolderPersistsAndTheDefaultKnownWordsPathFollows() {
        let chosen = URL(fileURLWithPath: "/Users/test/Meeting notes", isDirectory: true)
        sut.meetingsFolder = chosen
        XCTAssertEqual(defaults.string(forKey: "meetingsFolder"), chosen.path)
        let reopened = Settings(defaults: defaults, loginItem: loginItem)
        XCTAssertEqual(reopened.meetingsFolder, chosen)
        XCTAssertEqual(reopened.knownWordsFile, chosen.appendingPathComponent("known-words.md"))
        defaults.set("~/terms.md", forKey: "knownWordsFile")
        sut.meetingsFolder = URL(fileURLWithPath: "/Users/test/Other notes")
        XCTAssertEqual(reopened.knownWordsFile.path, NSHomeDirectory() + "/terms.md")
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
