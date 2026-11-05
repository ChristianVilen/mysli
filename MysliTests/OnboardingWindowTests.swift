import XCTest
@testable import Mysli

@MainActor
final class OnboardingWindowTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var settings: Settings!
    private var model: Onboarding!
    private var controller: SettingsWindowController!

    override func setUp() {
        suite = "OnboardingWindowTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        settings = Settings(defaults: defaults, loginItem: FakeLoginItem())
        model = Onboarding(settings: settings, defaults: defaults)
    }

    override func tearDown() {
        controller?.close()
        controller = nil
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeController(_ model: Onboarding) -> SettingsWindowController {
        let tools = ToolController(settings: settings, applyEffect: { _, _ in }, setCalendarReminders: { _ in })
        model.onApplyChoices = { tools.apply($0) }
        return SettingsWindowController(settings: settings, onboarding: model, present: { _ in },
                                        activation: .fake(), isWindowVisible: { _ in true })
    }

    func testSetupAndNormalPagesShareOneWindowAndPollOnlyOnTheAccessStep() throws {
        controller = makeController(model)
        var polling: [Bool] = []
        controller.onPermissionsVisibilityChanged = { polling.append($0) }
        let window = try XCTUnwrap(controller.window)
        controller.show(.meetings)
        let view = try XCTUnwrap(controller.onboardingView)
        XCTAssertTrue(window.contentView === view)
        view.nextButton.performClick(nil)
        try XCTUnwrap(view.toolButtons[.clipboard]).performClick(nil)
        view.nextButton.performClick(nil)
        XCTAssertEqual(polling, [true])
        XCTAssertFalse(settings.clipboardHistoryEnabled)
        controller.renderPermissions(.init(accessibility: true, screenRecording: true, microphone: .granted,
                                           calendar: .notDetermined, notifications: .notDetermined))
        XCTAssertFalse(try XCTUnwrap(view.permissionList.rows.first { $0.permission == .microphone }).view.grantButton.isEnabled)
        view.nextButton.performClick(nil)
        XCTAssertTrue(model.isFinished)
        XCTAssertTrue(controller.window === window)
        XCTAssertFalse(window.contentView === view)
        XCTAssertEqual(controller.selectedPage, .general)
        XCTAssertEqual(polling, [true, false])
    }

    func testReopeningAfterRestartUsesTheSavedStepWithoutWriting() throws {
        model.advance()
        model.advance()
        let resumed = Onboarding(settings: settings, defaults: defaults)
        controller = makeController(resumed)
        let before = defaults.persistentDomain(forName: suite)! as NSDictionary
        controller.show(.permissions)
        XCTAssertTrue(controller.window?.contentView === controller.onboardingView)
        XCTAssertEqual(resumed.step, .permissions)
        XCTAssertTrue(resumed.wasResumed)
        XCTAssertEqual(defaults.persistentDomain(forName: suite)! as NSDictionary, before)
        XCTAssertFalse(controller.showScreenshotSetupIfNeeded(issues: [.init(shortcut: .captureArea, failure: .systemConflict)]))
    }

    /// TEST_RUNNER_MYSLI_ONBOARDING_SNAPSHOTS=<folder> xcodebuild -project Mysli.xcodeproj -scheme Mysli test -only-testing:MysliTests/OnboardingWindowTests/testPictures
    func testPictures() throws {
        guard let path = ProcessInfo.processInfo.environment["MYSLI_ONBOARDING_SNAPSHOTS"] else {
            throw XCTSkip("Set MYSLI_ONBOARDING_SNAPSHOTS to write onboarding pictures.")
        }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        controller = makeController(model)
        controller.show()
        func capture(_ view: NSView, in window: NSWindow, name: String) throws {
            window.orderFront(nil)
            for (appearanceName, appearance, size) in [
                ("light", NSAppearance.Name.aqua, NSSize(width: 760, height: 700)),
                ("dark", .darkAqua, NSSize(width: 760, height: 700)),
                ("dark-compact", .darkAqua, NSSize(width: 640, height: 420))
            ] {
                window.appearance = NSAppearance(named: appearance)
                window.setContentSize(size)
                view.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                window.appearance?.performAsCurrentDrawingAppearance {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                }
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: folder.appendingPathComponent("\(name)-\(appearanceName).png"))
            }
        }
        for step in Onboarding.Step.allCases {
            if step == .permissions {
                controller.close()
                controller = makeController(Onboarding(settings: settings, defaults: defaults))
                controller.show()
            }
            let window = try XCTUnwrap(controller.window)
            let view = try XCTUnwrap(controller.onboardingView)
            controller.renderPermissions(.init(accessibility: true, screenRecording: true, microphone: .notDetermined,
                                               calendar: .notDetermined, notifications: .notDetermined))
            try capture(view, in: window, name: "onboarding-\(step.rawValue)")
            if step != .permissions { view.nextButton.performClick(nil) }
        }
        try XCTUnwrap(controller.onboardingView).nextButton.performClick(nil)
        for page in SettingsPage.allCases {
            controller.show(page)
            let window = try XCTUnwrap(controller.window)
            try capture(try XCTUnwrap(window.contentView), in: window, name: "settings-\(page.title.lowercased().replacingOccurrences(of: " ", with: "-"))")
        }
    }
}
