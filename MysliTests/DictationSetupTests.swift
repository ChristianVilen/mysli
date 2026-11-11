import XCTest
@testable import Mysli

@MainActor
final class DictationSetupTests: XCTestCase {
    func testSavedEnableLoadsWithoutWritesOrPromptsAndGrantStartsInput() async {
        let suite = "DictationSetupTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "dictationEnabled")
        let settings = Settings(defaults: defaults, loginItem: FakeLoginItem())
        var granted = false
        var prompts = 0
        let permissions = PermissionsManager(isAccessibilityTrusted: { granted }, hasScreenCaptureAccess: { false },
            microphoneAccess: { granted ? .granted : .notDetermined }, inputMonitoringAccess: { granted },
            requestMicrophoneAccess: { prompts += 1; return false }, openURL: { _ in prompts += 1; return true },
            showAccessibilityPrompt: { prompts += 1 }, defaults: defaults)
        let f = DictationFixture()
        var modes: [DictationKeyMode] = []
        let setup = DictationSetup(settings: settings, permissions: permissions, controller: f.controller,
                                   configureKey: { modes.append($0) }, requestFnPermission: { prompts += 1 })
        let before = defaults.persistentDomain(forName: suite)! as NSDictionary
        await permissions.refreshAndWait()
        setup.refresh()
        await f.waitFor(.idle)
        setup.refresh()
        XCTAssertEqual(modes, [.fn])
        XCTAssertNil(f.keys.receive)
        XCTAssertFalse(f.speech.session.released)
        XCTAssertEqual(prompts, 0)
        XCTAssertEqual(defaults.persistentDomain(forName: suite)! as NSDictionary, before)
        granted = true
        await permissions.refreshAndWait()
        setup.refresh()
        f.keys.receive?(.pressed)
        XCTAssertEqual(f.controller.presentation, .listening(level: 0, warning: false))
        granted = false
        await permissions.refreshAndWait()
        setup.refresh()
        XCTAssertEqual(f.controller.presentation, .idle)
        XCTAssertTrue(f.recorder.captures[0].cancelled)
        XCTAssertFalse(f.speech.session.released)
        XCTAssertEqual(prompts, 0)
        XCTAssertEqual(defaults.persistentDomain(forName: suite)! as NSDictionary, before)
        f.controller.shutdown()
    }

    func testKeyModeChangeRestartsInputAndKeepsSpeechLoaded() async {
        let suite = "DictationSetupTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults, loginItem: FakeLoginItem())
        settings.dictationEnabled = true
        let permissions = PermissionsManager(isAccessibilityTrusted: { true }, hasScreenCaptureAccess: { false },
            microphoneAccess: { .granted }, inputMonitoringAccess: { true }, defaults: defaults)
        let f = DictationFixture()
        var modes: [DictationKeyMode] = []
        let setup = DictationSetup(settings: settings, permissions: permissions, controller: f.controller,
                                   configureKey: { modes.append($0) }, requestFnPermission: {})
        await permissions.refreshAndWait()
        setup.refresh()
        await f.waitFor(.idle)
        let oldKeys = f.keys.receive
        settings.dictationKeyMode = .carbon
        setup.refresh()
        XCTAssertEqual(modes, [.fn, .carbon])
        XCTAssertEqual(f.controller.presentation, .idle)
        XCTAssertFalse(f.speech.session.released)
        oldKeys?(.pressed)
        XCTAssertTrue(f.recorder.captures.isEmpty)
        f.keys.receive?(.pressed)
        XCTAssertEqual(f.controller.presentation, .listening(level: 0, warning: false))
        f.controller.shutdown()
    }

    func testExplicitSetupRequestsOnlyThePermissionsForChosenMode() async {
        for mode in DictationKeyMode.allCases {
            let suite = "DictationSetupTests.\(UUID())"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = Settings(defaults: defaults, loginItem: FakeLoginItem())
            settings.dictationEnabled = true
            settings.dictationKeyMode = mode
            var requests: [String] = []
            let permissions = PermissionsManager(isAccessibilityTrusted: { false }, hasScreenCaptureAccess: { false },
                microphoneAccess: { .notDetermined }, inputMonitoringAccess: { false },
                requestMicrophoneAccess: { requests.append("mic"); return false },
                openURL: { _ in true }, showAccessibilityPrompt: { requests.append("ax") }, defaults: defaults)
            let f = DictationFixture()
            let setup = DictationSetup(settings: settings, permissions: permissions, controller: f.controller,
                configureKey: { _ in }, requestFnPermission: { requests.append("fn") })
            await setup.requestAccess()
            XCTAssertEqual(requests, mode == .fn ? ["ax", "fn", "mic"] : ["ax", "mic"])
            f.controller.shutdown()
        }
    }
    func testOptInAndPreferenceKeysSurviveReloadWithoutReadWrites() {
        let suite = "DictationSetupTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults, loginItem: FakeLoginItem())
        XCTAssertFalse(settings.enabledTools.contains(.dictation))
        XCTAssertEqual(settings.dictationKeyMode, .fn)
        XCTAssertTrue(settings.dictationNearbyText)
        let onboarding = Onboarding(settings: settings, defaults: defaults)
        XCTAssertFalse(onboarding.selectedTools.contains(.dictation))
        XCTAssertTrue(defaults.persistentDomain(forName: suite)?.isEmpty ?? true)
        onboarding.skip()
        XCTAssertFalse(onboarding.selectedTools.contains(.dictation))
        settings.setEnabled(.dictation, enabled: true)
        settings.dictationKeyMode = .carbon
        settings.dictationNearbyText = false
        XCTAssertEqual(defaults.object(forKey: "dictationEnabled") as? Bool, true)
        XCTAssertEqual(defaults.string(forKey: "dictationKeyMode"), "carbon")
        XCTAssertEqual(defaults.object(forKey: "dictationNearbyText") as? Bool, false)
        let reloaded = Settings(defaults: defaults, loginItem: FakeLoginItem())
        XCTAssertTrue(reloaded.enabledTools.contains(.dictation))
        XCTAssertEqual(reloaded.dictationKeyMode, .carbon)
        XCTAssertFalse(reloaded.dictationNearbyText)
    }

    func testPermissionsDependOnKeyModeAndNeverRequireScreenCapture() {
        XCTAssertEqual(RequiredPermissions(tools: [.dictation], calendarReminders: false,
                                           dictationKeyMode: .fn).permissions,
                       [.accessibility, .microphone, .inputMonitoring])
        XCTAssertEqual(RequiredPermissions(tools: [.dictation], calendarReminders: false,
                                           dictationKeyMode: .carbon).permissions,
                       [.accessibility, .microphone])
        XCTAssertEqual(RequiredPermissions(tools: [.meetings], calendarReminders: false).permissions,
                       [.screenRecording, .microphone])
    }

    func testFnSetupOpensMainKeyboardPaneWithoutChangingConflictDestination() {
        XCTAssertEqual(SettingsPane.keyboard.urls.first?.absoluteString,
                       "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
        XCTAssertEqual(SettingsPane.keyboardShortcuts.urls.first?.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts")
    }
}
