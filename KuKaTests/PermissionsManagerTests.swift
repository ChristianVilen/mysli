import XCTest
@testable import KuKa

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
        XCTAssertFalse(sut.allGranted)
    }

    func testOnChangeFiresWhenAStatusChanges() {
        var screenGranted = false
        let sut = PermissionsManager(
            isAccessibilityTrusted: { true },
            hasScreenCaptureAccess: { screenGranted }
        )
        sut.refresh()

        var changeCount = 0
        sut.onChange = { changeCount += 1 }

        screenGranted = true
        sut.refresh()

        XCTAssertEqual(changeCount, 1)
        XCTAssertTrue(sut.allGranted)
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
            hasScreenCaptureAccess: { true }
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
