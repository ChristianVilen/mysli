import XCTest
@testable import Mysli

@MainActor
final class PermissionsManagerTests: XCTestCase {
    private static let defaultsSuite = "PermissionsManagerTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: Self.defaultsSuite)!
        defaults.removePersistentDomain(forName: Self.defaultsSuite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: Self.defaultsSuite)
        super.tearDown()
    }

    func testRefreshReadsProbesAndUpdatesStatuses() {
        let sut = PermissionsManager(
            isAccessibilityTrusted: { true },
            hasScreenCaptureAccess: { false }
        )

        sut.refresh()

        XCTAssertTrue(sut.accessibility)
        XCTAssertFalse(sut.screenRecording)
    }

    func testOnChangeFiresWhenAStatusChanges() {
        var screenGranted = false
        let sut = PermissionsManager(
            isAccessibilityTrusted: { true },
            hasScreenCaptureAccess: { screenGranted },
            calendarAccess: { .full }
        )
        sut.refresh()

        var changeCount = 0
        sut.onChange = { changeCount += 1 }

        screenGranted = true
        sut.refresh()

        XCTAssertEqual(changeCount, 1)
    }

    func testOnChangeDoesNotFireWhenNothingChanged() {
        let sut = PermissionsManager(
            isAccessibilityTrusted: { true },
            hasScreenCaptureAccess: { true }
        )
        sut.refresh()

        var changeCount = 0
        sut.onChange = { changeCount += 1 }

        sut.refresh()

        XCTAssertEqual(changeCount, 0)
    }

    func testOpenSettingsFallsBackToLegacyURLWhenModernFails() {
        var opened: [URL] = []
        let sut = PermissionsManager(
            isAccessibilityTrusted: { false },
            hasScreenCaptureAccess: { false },
            openURL: { url in
                opened.append(url)
                return opened.count > 1
            }
        )

        sut.openSettings(.accessibility)

        XCTAssertEqual(opened.count, 2)
        XCTAssertTrue(opened[0].absoluteString.contains("com.apple.settings.PrivacySecurity.extension"))
        XCTAssertTrue(opened[1].absoluteString.contains("com.apple.preference.security"))
        XCTAssertTrue(opened.allSatisfy { $0.absoluteString.hasSuffix("Privacy_Accessibility") })
    }

    func testOpenSettingsStopsAfterModernURLSucceeds() {
        var opened: [URL] = []
        let sut = PermissionsManager(
            isAccessibilityTrusted: { false },
            hasScreenCaptureAccess: { false },
            openURL: { opened.append($0); return true }
        )

        sut.openSettings(.screenCapture)

        XCTAssertEqual(opened.count, 1)
        XCTAssertTrue(opened[0].absoluteString.hasSuffix("Privacy_ScreenCapture"))
    }

    func testMonitoringRefreshesWhenAppBecomesActive() {
        var axGranted = false
        let sut = PermissionsManager(
            isAccessibilityTrusted: { axGranted },
            hasScreenCaptureAccess: { true }
        )
        sut.refresh()

        let changed = expectation(description: "onChange fired on app activation")
        sut.onChange = { changed.fulfill() }

        axGranted = true
        sut.startMonitoring()
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        wait(for: [changed], timeout: 2)
        XCTAssertTrue(sut.accessibility)
    }

    func testPollingPicksUpAGrantWithoutManualRefresh() {
        var axGranted = false
        let sut = PermissionsManager(
            isAccessibilityTrusted: { axGranted },
            hasScreenCaptureAccess: { true },
            pollInterval: 0.001
        )
        sut.refresh()

        let changed = expectation(description: "onChange fired by the poll timer")
        sut.onChange = { changed.fulfill() }

        axGranted = true
        sut.startPolling()

        wait(for: [changed], timeout: 2)
        sut.stopPolling()
        XCTAssertTrue(sut.accessibility)
    }

    func testRefreshReadsTheMicrophoneAndReportsAChange() {
        var microphone = MicrophoneAccess.notDetermined
        let sut = PermissionsManager(isAccessibilityTrusted: { true }, hasScreenCaptureAccess: { true },
                                     microphoneAccess: { microphone })
        sut.refresh()
        var changeCount = 0
        sut.onChange = { changeCount += 1 }

        microphone = .granted
        sut.refresh()

        XCTAssertEqual(sut.microphone, .granted)
        XCTAssertEqual(changeCount, 1)
    }

    func testNotificationRefreshReadsStatusWithoutPrompting() async {
        var access = NotificationAccess.notDetermined
        var prompts = 0
        let sut = PermissionsManager(isAccessibilityTrusted: { false }, hasScreenCaptureAccess: { false },
                                     microphoneAccess: { .notDetermined }, notificationAccess: { access },
                                     requestNotificationAccess: { prompts += 1; return true })
        var changes = 0
        sut.onChange = { changes += 1 }
        await sut.refreshAndWait()
        XCTAssertEqual(changes, 0)
        access = .granted
        await sut.refreshAndWait()
        XCTAssertEqual(sut.snapshot.notifications, .granted)
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(prompts, 0)
    }

    func testRoutineRefreshIncludesNotificationsWithoutPrompting() async {
        var prompts = 0
        let sut = PermissionsManager(
            isAccessibilityTrusted: { true }, hasScreenCaptureAccess: { true },
            microphoneAccess: { .granted }, calendarAccess: { .full },
            notificationAccess: { .granted }, requestNotificationAccess: { prompts += 1; return true })
        sut.refresh()
        for _ in 0..<1_000 where sut.snapshot.notifications != .granted { await Task.yield() }
        XCTAssertEqual(sut.snapshot, PermissionSnapshot(accessibility: true, screenRecording: true,
                                                       microphone: .granted, calendar: .full, notifications: .granted))
        XCTAssertEqual(prompts, 0)
    }

    func testOlderNotificationReadCannotReplaceANewerGrant() async throws {
        var replies: [CheckedContinuation<NotificationAccess, Never>] = []
        let sut = PermissionsManager(
            isAccessibilityTrusted: { false }, hasScreenCaptureAccess: { false },
            microphoneAccess: { .notDetermined }, notificationAccess: {
                await withCheckedContinuation { replies.append($0) }
            })
        var published: [NotificationAccess] = []
        sut.onChange = { published.append(sut.snapshot.notifications) }
        defer { sut.onChange = nil }

        let older = Task { await sut.refreshAndWait() }
        for _ in 0..<1_000 where replies.count < 1 { await Task.yield() }
        let olderReply = try XCTUnwrap(replies.first)
        let newer = Task { await sut.refreshAndWait() }
        for _ in 0..<1_000 where replies.count < 2 { await Task.yield() }
        let newerReply = try XCTUnwrap(replies.dropFirst().first)

        newerReply.resume(returning: .granted)
        await newer.value
        olderReply.resume(returning: .denied)
        await older.value

        XCTAssertEqual(sut.snapshot.notifications, .granted)
        XCTAssertEqual(published, [.granted])
    }

    func testNotificationRequestAsksOnceThenOpensSettingsAfterDenial() async {
        var access = NotificationAccess.notDetermined
        var prompts = 0
        var opened: [String] = []
        let sut = PermissionsManager(isAccessibilityTrusted: { false }, hasScreenCaptureAccess: { false },
                                     microphoneAccess: { .notDetermined }, notificationAccess: { access }, requestNotificationAccess: {
            prompts += 1
            access = .denied
            return false
        }, openURL: { opened.append($0.absoluteString); return true })
        await sut.requestNotifications()
        XCTAssertEqual(prompts, 1)
        XCTAssertEqual(sut.snapshot.notifications, .denied)
        await sut.requestNotifications()
        XCTAssertEqual(prompts, 1)
        XCTAssertEqual(opened, ["x-apple.systempreferences:com.apple.Notifications-Settings.extension"])
        access = .granted
        await sut.requestNotifications()
        XCTAssertEqual(prompts, 1)
        XCTAssertEqual(opened.count, 1)
    }

    func testRequestCalendarAsksOnlyWhenNeverAskedAndThenOpensItsSettingsPane() async {
        var calendar = CalendarAccess.notDetermined
        var prompts = 0
        var opened: [String] = []
        let sut = PermissionsManager(isAccessibilityTrusted: { true }, hasScreenCaptureAccess: { true },
                                     calendarAccess: { calendar },
                                     requestCalendarAccess: { prompts += 1; calendar = .denied; return false },
                                     openURL: { opened.append($0.absoluteString); return true })
        sut.refresh()

        await sut.requestCalendar()
        XCTAssertEqual(prompts, 1)
        XCTAssertEqual(sut.calendar, .denied)
        XCTAssertEqual(opened, [])

        await sut.requestCalendar()
        XCTAssertEqual(prompts, 1, "macOS asks only once")
        XCTAssertEqual(opened, ["x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars"])
    }

    func testRequestMicrophoneShowsTheSystemPromptWhenNeverAsked() async {
        var microphone = MicrophoneAccess.notDetermined
        var prompts = 0
        let sut = PermissionsManager(isAccessibilityTrusted: { true }, hasScreenCaptureAccess: { true },
                                     microphoneAccess: { microphone },
                                     requestMicrophoneAccess: { prompts += 1; microphone = .granted; return true })
        sut.refresh()

        let granted = await sut.requestMicrophone()

        XCTAssertTrue(granted)
        XCTAssertEqual(prompts, 1)
        XCTAssertEqual(sut.microphone, .granted)
    }

    func testRequestMicrophoneOpensItsSettingsPaneWhenDenied() async {
        var opened: [String] = []
        var prompts = 0
        let sut = PermissionsManager(isAccessibilityTrusted: { true }, hasScreenCaptureAccess: { true },
                                     microphoneAccess: { .denied },
                                     requestMicrophoneAccess: { prompts += 1; return false },
                                     openURL: { opened.append($0.absoluteString); return true })
        sut.refresh()

        let granted = await sut.requestMicrophone()

        XCTAssertFalse(granted)
        XCTAssertEqual(prompts, 0)
        XCTAssertEqual(opened, ["x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone"])
    }

    // MARK: - Accessibility prompt

    func testAccessibilityPromptShowsOnlyOnTheFirstRequest() {
        var prompts = 0
        var opened = 0
        let sut = PermissionsManager(
            isAccessibilityTrusted: { false },
            hasScreenCaptureAccess: { false },
            openURL: { _ in opened += 1; return true },
            showAccessibilityPrompt: { prompts += 1 },
            defaults: defaults
        )

        sut.requestAccessibility()
        sut.requestAccessibility()

        XCTAssertEqual(prompts, 1)
        XCTAssertEqual(opened, 2, "The Settings pane should open on every request")
    }

    func testAccessibilityPromptIsNotShownAgainInALaterRun() {
        var prompts = 0
        func makeSUT() -> PermissionsManager {
            PermissionsManager(
                isAccessibilityTrusted: { false },
                hasScreenCaptureAccess: { false },
                openURL: { _ in true },
                showAccessibilityPrompt: { prompts += 1 },
                defaults: defaults
            )
        }

        makeSUT().requestAccessibility()
        makeSUT().requestAccessibility()

        XCTAssertEqual(prompts, 1)
    }
}
