#if DEBUG
import AppKit
import SwiftUI

#Preview("Settings · General", traits: .fixedLayout(width: 760, height: 700)) {
    SettingsPreviews.page(.general)
}

#Preview("Settings · Screenshots", traits: .fixedLayout(width: 760, height: 700)) {
    SettingsPreviews.page(.screenshots)
}

#Preview("Settings · Clipboard", traits: .fixedLayout(width: 760, height: 700)) {
    SettingsPreviews.page(.clipboard)
}

#Preview("Settings · Windows", traits: .fixedLayout(width: 760, height: 700)) {
    SettingsPreviews.page(.windows)
}

#Preview("Settings · Keep Awake", traits: .fixedLayout(width: 760, height: 700)) {
    SettingsPreviews.page(.keepAwake)
}

#Preview("Settings · Meetings", traits: .fixedLayout(width: 760, height: 700)) {
    SettingsPreviews.page(.meetings)
}

#Preview("Settings · Dictation", traits: .fixedLayout(width: 760, height: 700)) {
    SettingsPreviews.page(.dictation)
}

#Preview("Settings · Permissions", traits: .fixedLayout(width: 760, height: 700)) {
    SettingsPreviews.page(.permissions)
}

#Preview("Settings · Help", traits: .fixedLayout(width: 760, height: 700)) {
    SettingsPreviews.page(.help)
}

#Preview("Settings search · Results", traits: .fixedLayout(width: 760, height: 700)) {
    SettingsPreviews.page(.general, query: "sleep")
}

#Preview("Settings search · No results", traits: .fixedLayout(width: 760, height: 700)) {
    SettingsPreviews.page(.general, query: "wallpaper")
}

#Preview("Settings search · Open guide", traits: .fixedLayout(width: 760, height: 700)) {
    SettingsPreviews.page(.general, query: "combining screenshots", openFirstResult: true)
}

#Preview("Settings sidebar", traits: .fixedLayout(width: 230, height: 460)) {
    SettingsPreviews.sidebar()
}

#Preview("Permission list", traits: .fixedLayout(width: 520, height: 420)) {
    SettingsPreviews.permissionList()
}

@MainActor
enum SettingsPreviews {
    static let permissionSnapshot = PermissionSnapshot(accessibility: true, screenRecording: false,
                                                       microphone: .notDetermined, calendar: .full,
                                                       notifications: .notDetermined)

    static func page(_ page: SettingsPage, query: String? = nil, openFirstResult: Bool = false) -> NSViewController {
        let defaults = PreviewDefaults()
        let settings = Settings(defaults: defaults.values, loginItem: PreviewLoginItem())
        settings.meetingsFolder = URL(fileURLWithPath: "/Users/example/Meetings", isDirectory: true)
        settings.meetingContextFile = URL(fileURLWithPath: "/Users/example/Meetings/background.md")
        settings.dictationEnabled = true
        settings.calendarRecordingRemindersEnabled = true
        return controller(settings: settings, tools: tools(for: settings))
            .makePreview(retaining: defaults, page: page, query: query, openFirstResult: openFirstResult)
    }

    static func controller(settings: Settings, tools: ToolController,
                           onboarding: Onboarding? = nil) -> SettingsWindowController {
        let controller = SettingsWindowController(
            settings: settings, onboarding: onboarding, permissionActions: .inert, openURL: { _ in },
            chooseFolder: { _, _, completion in completion(nil) },
            chooseContext: { _, _, completion in completion(nil) },
            present: { _ in }, isWindowVisible: { _ in false })
        tools.onChange = { [weak controller] in controller?.refresh() }
        controller.onToolChanged = { tool, enabled in tools.setEnabled(tool, enabled: enabled) }
        controller.onCalendarRemindersChanged = { enabled in tools.setCalendarReminders(enabled) }
        controller.renderPermissions(permissionSnapshot)
        return controller
    }

    static func tools(for settings: Settings) -> ToolController {
        ToolController(settings: settings, applyEffect: { _, _ in }, setCalendarReminders: { enabled in
            settings.calendarRecordingRemindersEnabled = enabled
        })
    }

    static func sidebar() -> NSViewController {
        let defaults = PreviewDefaults()
        let settings = Settings(defaults: defaults.values, loginItem: PreviewLoginItem())
        return controller(settings: settings, tools: tools(for: settings)).makeSidebarPreview(retaining: defaults)
    }

    static func permissionList() -> NSViewController {
        let list = PermissionListView(actions: .inert)
        list.showRequired(RequiredPermissions(tools: Set(MysliTool.allCases), calendarReminders: true))
        list.render(permissionSnapshot)
        let stack = SettingsLayout.stack()
        SettingsLayout.add(list, to: stack)
        let background = SettingsBackground()
        SettingsLayout.fill(SettingsLayout.scroll(stack), in: background)
        return AppKitPreview.host(background, size: NSSize(width: 520, height: 420))
    }
}

final class PreviewLoginItem: LoginItemManaging {
    private(set) var isEnabled = false

    func setEnabled(_ enabled: Bool) throws {
        isEnabled = enabled
    }
}
#endif
