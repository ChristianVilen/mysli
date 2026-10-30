import AppKit
import UserNotifications

enum NotificationClick: Equatable {
    case open(URL)
    case checkWords(MeetingFolder)

    /// "url" is also the key of every notification before Check Words, so those still open.
    private static let openKey = "url"
    private static let checkWordsKey = "checkWords"

    var userInfo: [String: String] {
        switch self {
        case .open(let url): return [Self.openKey: url.absoluteString]
        case .checkWords(let meeting): return [Self.checkWordsKey: meeting.url.absoluteString]
        }
    }

    init?(userInfo: [AnyHashable: Any]) {
        if let string = userInfo[Self.checkWordsKey] as? String, let url = URL(string: string) {
            self = .checkWords(MeetingFolder(url: url))
        } else if let string = userInfo[Self.openKey] as? String, let url = URL(string: string) {
            self = .open(url)
        } else {
            return nil
        }
    }
}

protocol Notifying {
    /// Call when the user starts something that will notify later, so the
    /// macOS prompt appears while its reason is clear.
    func requestPermission()
    func post(title: String, body: String, onClick: NotificationClick?)
}

/// `AppDelegate` must install this as the notification center's delegate to handle clicks.
final class SystemNotifier: NSObject, Notifying, UNUserNotificationCenterDelegate {
    static let shared = SystemNotifier()

    private var didRequestPermission = false
    private let open: (URL) -> Void

    var onCheckWords: (@MainActor (MeetingFolder) -> Void)?
    var onCalendarReminder: (@MainActor (CalendarReminderAction, UUID) async -> Void)?

    @MainActor
    func routeCalendarReminder(category: String, action: String, userInfo: [AnyHashable: Any]) async -> Bool {
        guard let response = CalendarReminderNotifications.decode(category: category, action: action, userInfo: userInfo)
        else { return false }
        await onCalendarReminder?(response.action, response.token)
        return true
    }

    init(open: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.open = open
    }

    func requestPermission() {
        guard !didRequestPermission else { return }
        didRequestPermission = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    func post(title: String, body: String, onClick click: NotificationClick?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let click { content.userInfo = click.userInfo }
        // A unique identifier, so two meetings' notices do not replace each other.
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    @MainActor
    func perform(_ click: NotificationClick) {
        switch click {
        case .open(let url): open(url)
        case .checkWords(let meeting): onCheckWords?(meeting)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            let content = response.notification.request.content
            await self.handleResponse(category: content.categoryIdentifier, action: response.actionIdentifier,
                                      userInfo: content.userInfo, completion: completionHandler)
        }
    }

    @MainActor
    func handleResponse(category: String, action: String, userInfo: [AnyHashable: Any], completion: () -> Void) async {
        defer { completion() }
        if await routeCalendarReminder(category: category, action: action, userInfo: userInfo) { return }
        if let click = NotificationClick(userInfo: userInfo) { perform(click) }
    }

    /// Without this, macOS hides a notification while Ku-Ka is the active app,
    /// for example while its menu is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
