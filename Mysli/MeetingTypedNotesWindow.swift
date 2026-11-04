import AppKit

@MainActor
final class MeetingTypedNotesHost: NSWindowController, NSWindowDelegate {
    private let notesView: MeetingTypedNotesView
    private let activation: OrdinaryWindowActivation
    private let present: @MainActor (NSWindow) -> Void
    var onClose: (() -> Void)?

    init(view: MeetingTypedNotesView,
         activation: OrdinaryWindowActivation = .shared,
         present: @escaping @MainActor (NSWindow) -> Void = { $0.makeKeyAndOrderFront(nil) }) {
        notesView = view
        self.activation = activation
        self.present = present
        let panel = HistoricalNotesPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                                         styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
        panel.title = view.session.meeting.title
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.contentMinSize = NSSize(width: 460, height: 330)
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        panel.center()
        super.init(window: panel)
        panel.delegate = self
    }

    convenience init(session: MeetingTypedNotesSession, requestUpdate: @escaping () -> Void,
                     activation: OrdinaryWindowActivation = .shared,
                     present: @escaping @MainActor (NSWindow) -> Void = { $0.makeKeyAndOrderFront(nil) },
                     confirmReload: (@MainActor (NSWindow) -> Bool)? = nil) {
        let view: MeetingTypedNotesView
        if let confirmReload {
            view = MeetingTypedNotesView(session: session, requestUpdate: requestUpdate, confirmReload: confirmReload)
        } else {
            view = MeetingTypedNotesView(session: session, requestUpdate: requestUpdate)
        }
        self.init(view: view, activation: activation, present: present)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        guard let window else { return }
        activation.open(window)
        present(window)
        notesView.focus()
    }

    func windowWillClose(_ notification: Notification) {
        if let window { activation.close(window) }
        onClose?()
    }

    func detach() {
        guard let window else { return }
        activation.close(window)
        window.delegate = nil
        window.contentView = nil
        close()
    }
}

private final class HistoricalNotesPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
