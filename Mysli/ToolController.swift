import Foundation

struct ToolSelection: Equatable {
    let tools: Set<MysliTool>
    let calendarReminders: Bool

    init(tools: Set<MysliTool>, calendarReminders: Bool) {
        self.tools = tools
        self.calendarReminders = tools.contains(.meetings) && calendarReminders
    }
}

@MainActor
final class ToolController {
    var onChange: (() -> Void)?
    private let settings: Settings
    private let applyEffect: @MainActor (MysliTool, Bool) -> Void
    private let applyCalendarReminders: @MainActor (Bool) async -> Void
    private var requestedReminders: Bool

    init(settings: Settings,
         applyEffect: @escaping @MainActor (MysliTool, Bool) -> Void,
         setCalendarReminders: @escaping @MainActor (Bool) async -> Void) {
        self.settings = settings
        self.applyEffect = applyEffect
        applyCalendarReminders = setCalendarReminders
        requestedReminders = settings.meetingsEnabled && settings.calendarRecordingRemindersEnabled
    }

    @discardableResult
    func setEnabled(_ tool: MysliTool, enabled: Bool) -> Task<Void, Never> {
        var tools = settings.enabledTools
        if enabled { tools.insert(tool) } else { tools.remove(tool) }
        return apply(ToolSelection(tools: tools, calendarReminders: requestedReminders))
    }

    @discardableResult
    func setCalendarReminders(_ enabled: Bool) -> Task<Void, Never> {
        apply(ToolSelection(tools: settings.enabledTools, calendarReminders: enabled))
    }

    @discardableResult
    func apply(_ selection: ToolSelection) -> Task<Void, Never> {
        let before = settings.enabledTools
        let changed = MysliTool.allCases.filter { before.contains($0) != selection.tools.contains($0) }
        requestedReminders = selection.calendarReminders
        for tool in changed { settings.setEnabled(tool, enabled: selection.tools.contains(tool)) }
        for tool in changed { applyEffect(tool, selection.tools.contains(tool)) }
        if !changed.isEmpty { onChange?() }
        return Task { [weak self] in
            guard let self, requestedReminders == selection.calendarReminders,
                  settings.calendarRecordingRemindersEnabled != selection.calendarReminders else { return }
            await applyCalendarReminders(selection.calendarReminders)
            onChange?()
        }
    }
}
