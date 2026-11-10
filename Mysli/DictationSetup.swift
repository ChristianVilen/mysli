import Foundation

@MainActor
final class DictationSetup {
    private let settings: Settings
    private let permissions: PermissionsManager
    private let controller: DictationController
    private let configureKey: (DictationKeyMode) -> Void
    private let requestFnPermission: () -> Void
    private var configuredMode: DictationKeyMode?

    init(settings: Settings, permissions: PermissionsManager, controller: DictationController,
         configureKey: @escaping (DictationKeyMode) -> Void, requestFnPermission: @escaping () -> Void) {
        self.settings = settings
        self.permissions = permissions
        self.controller = controller
        self.configureKey = configureKey
        self.requestFnPermission = requestFnPermission
    }

    func refresh() {
        let mode = settings.dictationKeyMode
        if configuredMode != mode {
            controller.setEnabled(false)
            configuredMode = mode
            configureKey(mode)
        }
        let required = RequiredPermissions(tools: [.dictation], calendarReminders: false, dictationKeyMode: mode)
        controller.setAccess(required.allGranted(in: permissions.snapshot))
        controller.setEnabled(settings.dictationEnabled)
    }

    func requestAccess() async {
        guard settings.dictationEnabled else { return }
        permissions.refresh()
        refresh()
        if !permissions.accessibility { permissions.requestAccessibility() }
        if settings.dictationKeyMode == .fn && !permissions.inputMonitoring { requestFnPermission() }
        _ = await permissions.requestMicrophone()
        guard settings.dictationEnabled, !Task.isCancelled else { return }
        await permissions.refreshAndWait()
        guard settings.dictationEnabled, !Task.isCancelled else { return }
        refresh()
    }
}
