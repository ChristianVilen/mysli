import XCTest
@testable import Mysli

final class OnboardingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var settings: Settings!
    private var sut: Onboarding!

    override func setUp() {
        suite = "OnboardingTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        settings = Settings(defaults: defaults, loginItem: FakeLoginItem())
        sut = Onboarding(settings: settings, defaults: defaults)
    }

    override func tearDown() {
        sut = nil
        defaults.removePersistentDomain(forName: suite)
    }

    private func reload() -> Onboarding { Onboarding(settings: settings, defaults: defaults) }

    func testFirstLaunchSelectsAllToolsWithoutRemindersAndWritesNothing() {
        XCTAssertEqual(sut.step, .welcome)
        XCTAssertFalse(sut.isFinished)
        XCTAssertEqual(sut.selectedTools, Set(MysliTool.allCases))
        XCTAssertFalse(sut.calendarReminders)
        XCTAssertTrue(defaults.persistentDomain(forName: suite)?.isEmpty ?? true)
    }

    func testChoicesAndStepPersistBeforeToolsAreApplied() {
        sut.advance()
        sut.setTool(.clipboard, enabled: false)
        sut.setCalendarReminders(true)
        XCTAssertEqual(defaults.string(forKey: "onboardingStep"), "tools")
        XCTAssertEqual(defaults.stringArray(forKey: "onboardingTools"), ["keepAwake", "meetings", "screenshots", "windows"])
        XCTAssertEqual(defaults.object(forKey: "onboardingCalendarReminders") as? Bool, true)
        let resumed = reload()
        XCTAssertEqual(resumed.step, .tools)
        XCTAssertFalse(resumed.selectedTools.contains(.clipboard))
        XCTAssertTrue(resumed.calendarReminders)
        XCTAssertTrue(settings.clipboardHistoryEnabled)
        XCTAssertFalse(settings.calendarRecordingRemindersEnabled)
    }

    func testContinuingAppliesToolsAndSavesAccessStepBeforeRequestingReminders() {
        sut.advance()
        for tool in [MysliTool.screenshots, .windows, .keepAwake] { sut.setTool(tool, enabled: false) }
        sut.setCalendarReminders(true)
        var applied: [Bool] = []
        sut.onApplyChoices = { reminders in
            XCTAssertEqual(self.reload().step, .permissions)
            XCTAssertEqual(self.settings.enabledTools, [.clipboard, .meetings])
            applied.append(reminders)
        }
        sut.advance()
        XCTAssertEqual(applied, [true])
        XCTAssertFalse(settings.calendarRecordingRemindersEnabled, "only the reminder controller writes this preference")
        XCTAssertEqual(sut.requiredPermissions.permissions, [.accessibility, .screenRecording, .microphone, .calendar, .notifications])
        XCTAssertTrue(reload().wasResumed)
    }

    func testTurningMeetingsOffClearsItsReminderChoice() {
        sut.advance()
        sut.setCalendarReminders(true)
        sut.setTool(.meetings, enabled: false)
        sut.setCalendarReminders(true)
        XCTAssertFalse(sut.calendarReminders)
        XCTAssertEqual(sut.requiredPermissions.permissions, [.accessibility, .screenRecording])
        sut.setTool(.meetings, enabled: true)
        XCTAssertFalse(sut.calendarReminders)
    }

    func testBackKeepsDraftChoicesWithoutChangingAppliedTools() {
        sut.advance()
        sut.setTool(.clipboard, enabled: false)
        sut.back()
        XCTAssertEqual(reload().step, .welcome)
        sut.advance()
        XCTAssertFalse(sut.selectedTools.contains(.clipboard))
        sut.advance()
        XCTAssertFalse(settings.clipboardHistoryEnabled)
        sut.back()
        XCTAssertEqual(reload().step, .tools)
    }

    func testSkipRestoresAllToolsAndDoesNotApplyUnsubmittedReminders() {
        settings.screenshotShortcutsEnabled = false
        sut.advance()
        sut.setTool(.meetings, enabled: false)
        sut.setTool(.meetings, enabled: true)
        sut.setCalendarReminders(true)
        var applied: [Bool] = []
        sut.onApplyChoices = { applied.append($0) }
        sut.skip()
        XCTAssertTrue(reload().isFinished)
        XCTAssertEqual(defaults.object(forKey: "onboardingFinished") as? Bool, true)
        XCTAssertEqual(settings.enabledTools, Set(MysliTool.allCases))
        XCTAssertEqual(applied, [false])
    }

    func testFinishAllowsMissingAccessAndLaterLaunchUsesEnabledTools() {
        let missing = PermissionSnapshot(accessibility: false, screenRecording: false, microphone: .denied,
                                         calendar: .denied, notifications: .denied)
        XCTAssertEqual(sut.launchDestination(for: missing), .onboarding)
        sut.advance()
        for tool in MysliTool.allCases where tool != .keepAwake { sut.setTool(tool, enabled: false) }
        sut.advance()
        sut.advance()
        XCTAssertTrue(reload().isFinished)
        XCTAssertEqual(reload().launchDestination(for: missing), .none)
        settings.meetingsEnabled = true
        XCTAssertEqual(reload().launchDestination(for: missing), .permissions)
        let granted = PermissionSnapshot(accessibility: false, screenRecording: true, microphone: .granted,
                                         calendar: .denied, notifications: .denied)
        XCTAssertEqual(reload().launchDestination(for: granted), .none)
    }

    func testUnknownSavedValuesAreReadWithoutWriting() {
        defaults.set("future", forKey: "onboardingStep")
        defaults.set(["meetings", "future"], forKey: "onboardingTools")
        let before = defaults.persistentDomain(forName: suite)! as NSDictionary
        let resumed = reload()
        XCTAssertEqual(resumed.step, .welcome)
        XCTAssertEqual(resumed.selectedTools, [.meetings])
        XCTAssertEqual(defaults.persistentDomain(forName: suite)! as NSDictionary, before)
    }
}
