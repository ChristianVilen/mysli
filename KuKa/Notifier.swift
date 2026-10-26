import AppKit
import UserNotifications

protocol Notifying {
    /// Call when the user starts something that will notify later, so the
    /// macOS prompt appears while its reason is clear.
    func requestPermission()
    /// `url` opens when the user clicks the notification.
    func post(title: String, body: String, opening url: URL?)
}

/// The one way Ku-Ka posts notifications. `AppDelegate` installs it as the
/// notification center's delegate, so a click opens the notification's file.
final class SystemNotifier: NSObject, Notifying, UNUserNotificationCenterDelegate {
    static let shared = SystemNotifier()

    private static let urlKey = "url"
    private var didRequestPermission = false

    func requestPermission() {
        guard !didRequestPermission else { return }
        didRequestPermission = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    func post(title: String, body: String, opening url: URL?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let url { content.userInfo = [Self.urlKey: url.absoluteString] }
        // A unique identifier, so two meetings' notices do not replace each other.
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let string = response.notification.request.content.userInfo[Self.urlKey] as? String,
           let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }

    /// Without this, macOS hides a notification while Ku-Ka is the active app,
    /// for example while its menu is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
