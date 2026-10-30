import AppKit
import EventKit

@MainActor
final class CalendarReminderDriver: CalendarReminderDriving {
    struct Calls {
        var observe: (@escaping @MainActor () -> Void) -> () -> Void
        var timer: (Date, TimeInterval, @escaping @MainActor () -> Void) -> () -> Void
        var now: () -> Date = Date.init
    }
    private let calls: Calls
    private var onChange: (@MainActor () -> Void)?
    private var cancelSignals: (() -> Void)?
    private var cancelSafety: (() -> Void)?
    private var cancelBoundary: (() -> Void)?
    init(calls: Calls) { self.calls = calls }

    convenience init() {
        self.init(calls: Calls(observe: { callback in
            let center = NotificationCenter.default
            let workspace = NSWorkspace.shared.notificationCenter
            let names: [Notification.Name] = [.EKEventStoreChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange]
            let observers = names.map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    Task { @MainActor in callback() }
                }
            }
            let wake = workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in callback() }
            }
            return {
                observers.forEach(center.removeObserver)
                workspace.removeObserver(wake)
            }
        }, timer: { date, interval, callback in
            let timer = Timer(fire: date, interval: interval, repeats: interval > 0) { _ in
                Task { @MainActor in callback() }
            }
            RunLoop.main.add(timer, forMode: .common)
            return { timer.invalidate() }
        }))
    }

    func start(onChange: @escaping @MainActor () -> Void) {
        stop()
        self.onChange = onChange
        cancelSignals = calls.observe(onChange)
        cancelSafety = calls.timer(calls.now().addingTimeInterval(60), 60, onChange)
    }
    func schedule(at: Date?) {
        cancelBoundary?()
        cancelBoundary = nil
        guard let at, let onChange else { return }
        cancelBoundary = calls.timer(at, 0, onChange)
    }
    func stop() {
        cancelBoundary?()
        cancelSafety?()
        cancelSignals?()
        cancelBoundary = nil
        cancelSafety = nil
        cancelSignals = nil
        onChange = nil
    }
}
