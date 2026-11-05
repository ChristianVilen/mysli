import XCTest
@testable import Mysli

@MainActor
final class ToolControllerTests: XCTestCase {
    private struct Change: Equatable {
        let tool: MysliTool
        let enabled: Bool
    }

    private var suite: String!
    private var defaults: UserDefaults!
    private var settings: Settings!
    private var sut: ToolController!
    private var effects: [Change] = []
    private var savedAtEffect: [Set<MysliTool>] = []
    private var reminderChanges: [Bool] = []

    override func setUp() {
        suite = "ToolControllerTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        settings = Settings(defaults: defaults, loginItem: FakeLoginItem())
    }

    override func tearDown() {
        sut = nil
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeController() -> ToolController {
        ToolController(settings: settings, applyEffect: { [unowned self] tool, enabled in
            effects.append(Change(tool: tool, enabled: enabled))
            savedAtEffect.append(settings.enabledTools)
        }, setCalendarReminders: { [unowned self] enabled in
            reminderChanges.append(enabled)
            settings.calendarRecordingRemindersEnabled = enabled
        })
    }

    func testSelectionSavesAllToolsBeforeApplyingLiveEffects() async {
        sut = makeController()
        let selection = ToolSelection(tools: [.meetings], calendarReminders: true)
        await sut.apply(selection).value

        XCTAssertEqual(settings.enabledTools, [.meetings])
        XCTAssertEqual(effects, [Change(tool: .screenshots, enabled: false),
                                 Change(tool: .clipboard, enabled: false),
                                 Change(tool: .windows, enabled: false), Change(tool: .keepAwake, enabled: false)])
        XCTAssertEqual(savedAtEffect, [[.meetings], [.meetings], [.meetings], [.meetings]])
        XCTAssertEqual(reminderChanges, [true])
        XCTAssertTrue(settings.calendarRecordingRemindersEnabled)
    }

    func testSingleToolChangeKeepsOtherChoicesAndDoesNotApplyAnUnchangedToolAgain() async {
        sut = makeController()
        await sut.setEnabled(.windows, enabled: false).value
        await sut.setEnabled(.windows, enabled: false).value
        XCTAssertEqual(settings.enabledTools, [.screenshots, .clipboard, .keepAwake, .meetings])
        XCTAssertEqual(effects, [Change(tool: .windows, enabled: false)])
        XCTAssertTrue(reminderChanges.isEmpty)
    }

    func testTurningMeetingsBackOnKeepsRemindersOffWhileDisableIsPending() async {
        settings.calendarRecordingRemindersEnabled = true
        sut = makeController()
        let off = sut.setEnabled(.meetings, enabled: false)
        let on = sut.setEnabled(.meetings, enabled: true)
        await off.value
        await on.value
        XCTAssertTrue(settings.meetingsEnabled)
        XCTAssertFalse(settings.calendarRecordingRemindersEnabled)
        XCTAssertEqual(reminderChanges, [false])
        XCTAssertEqual(effects, [Change(tool: .meetings, enabled: false), Change(tool: .meetings, enabled: true)])
    }

    func testUnstartedReminderChoiceDoesNotPromptAfterItIsTurnedOff() async {
        sut = makeController()
        let on = sut.setCalendarReminders(true)
        let off = sut.setCalendarReminders(false)
        await on.value
        await off.value
        XCTAssertFalse(settings.calendarRecordingRemindersEnabled)
        XCTAssertTrue(reminderChanges.isEmpty)
    }

    func testRemindersCannotBeEnabledWithoutMeetings() async {
        settings.meetingsEnabled = false
        sut = makeController()
        await sut.setCalendarReminders(true).value
        XCTAssertFalse(settings.calendarRecordingRemindersEnabled)
        XCTAssertTrue(reminderChanges.isEmpty)
    }

    func testReminderChoiceNotifiesAfterThePreferenceIsApplied() async {
        sut = makeController()
        var savedChoices: [Bool] = []
        sut.onChange = { [unowned self] in savedChoices.append(settings.calendarRecordingRemindersEnabled) }
        let applying = sut.setCalendarReminders(true)
        XCTAssertTrue(savedChoices.isEmpty)
        await applying.value
        XCTAssertEqual(savedChoices, [true])
    }
}
