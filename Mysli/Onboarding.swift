import Foundation

final class Onboarding {
    enum Step: String, CaseIterable { case welcome, tools, permissions }
    enum LaunchDestination { case onboarding, permissions, none }

    private(set) var step: Step
    private(set) var selectedTools: Set<MysliTool>
    private(set) var calendarReminders: Bool
    private(set) var isFinished: Bool
    let wasResumed: Bool
    var onApplyChoices: ((ToolSelection) -> Void)?
    private let settings: Settings
    private let defaults: UserDefaults

    init(settings: Settings, defaults: UserDefaults) {
        self.settings = settings
        self.defaults = defaults
        step = defaults.string(forKey: "onboardingStep").flatMap(Step.init(rawValue:)) ?? .welcome
        selectedTools = defaults.stringArray(forKey: "onboardingTools")
            .map { Set($0.compactMap(MysliTool.init(rawValue:))) } ?? MysliTool.defaultSelection
        calendarReminders = selectedTools.contains(.meetings) && defaults.bool(forKey: "onboardingCalendarReminders")
        isFinished = defaults.bool(forKey: "onboardingFinished")
        wasResumed = step == .permissions && !isFinished
    }

    var requiredPermissions: RequiredPermissions {
        RequiredPermissions(tools: selectedTools, calendarReminders: calendarReminders,
                            dictationKeyMode: settings.dictationKeyMode)
    }

    func advance() {
        guard !isFinished else { return }
        switch step {
        case .welcome:
            saveStep(.tools)
        case .tools:
            saveStep(.permissions)
            onApplyChoices?(ToolSelection(tools: selectedTools, calendarReminders: calendarReminders))
        case .permissions:
            finish()
        }
    }

    func back() {
        guard !isFinished else { return }
        switch step {
        case .welcome: break
        case .tools: saveStep(.welcome)
        case .permissions: saveStep(.tools)
        }
    }

    func setTool(_ tool: MysliTool, enabled: Bool) {
        guard step == .tools, !isFinished else { return }
        if enabled { selectedTools.insert(tool) } else { selectedTools.remove(tool) }
        if !selectedTools.contains(.meetings) { calendarReminders = false }
        saveChoices()
    }

    func setCalendarReminders(_ enabled: Bool) {
        guard step == .tools, !isFinished else { return }
        calendarReminders = enabled && selectedTools.contains(.meetings)
        saveChoices()
    }

    func skip() {
        guard !isFinished else { return }
        selectedTools = MysliTool.defaultSelection
        calendarReminders = settings.calendarRecordingRemindersEnabled
        saveChoices()
        finish()
        onApplyChoices?(ToolSelection(tools: selectedTools, calendarReminders: calendarReminders))
    }

    func launchDestination(for snapshot: PermissionSnapshot) -> LaunchDestination {
        if !isFinished { return .onboarding }
        return settings.requiredPermissions.allGranted(in: snapshot) ? .none : .permissions
    }

    private func saveChoices() {
        defaults.set(selectedTools.map(\.rawValue).sorted(), forKey: "onboardingTools")
        defaults.set(calendarReminders, forKey: "onboardingCalendarReminders")
    }

    private func saveStep(_ step: Step) {
        self.step = step
        defaults.set(step.rawValue, forKey: "onboardingStep")
    }

    private func finish() {
        isFinished = true
        defaults.set(true, forKey: "onboardingFinished")
    }
}
