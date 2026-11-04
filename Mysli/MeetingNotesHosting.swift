import AppKit

/// The one place in the floating panel where a notes editor goes.
@MainActor
protocol MeetingNotesSlot: AnyObject {
    func attachNotes(_ view: MeetingTypedNotesView)
    func detachNotes()
    /// The user closed the notes in the panel. The owner detaches them.
    var onCloseNotes: (() -> Void)? { get set }
}

/// Decides where each open notes editor is: in the panel while its meeting records, and in its
/// own window otherwise. Each meeting keeps one view, so a move keeps the draft, the cursor, and
/// undo. A new recording takes the panel, so the notes of the meeting before move to a window.
@MainActor
final class MeetingNotesHosting {
    private let panel: MeetingNotesSlot
    private let recorder: MeetingRecorder
    private let notes: MeetingNotesController
    private let makeWindow: (MeetingTypedNotesView) -> MeetingTypedNotesHost
    /// Also holds a closed editor whose draft is not saved, so the next open shows that draft.
    private var views: [MeetingFolder: MeetingTypedNotesView] = [:]
    private var panelMeeting: MeetingFolder?
    private var windows: [MeetingFolder: MeetingTypedNotesHost] = [:]

    init(panel: MeetingNotesSlot, recorder: MeetingRecorder, notes: MeetingNotesController,
         makeWindow: @escaping (MeetingTypedNotesView) -> MeetingTypedNotesHost = { MeetingTypedNotesHost(view: $0) }) {
        self.panel = panel
        self.recorder = recorder
        self.notes = notes
        self.makeWindow = makeWindow
        panel.onCloseNotes = { [weak self] in self?.closePanelNotes() }
    }

    func open(_ meeting: MeetingFolder) throws {
        let view = try views[meeting] ?? makeView(for: meeting)
        views[meeting] = view
        if meeting == recorder.activeMeeting {
            panelMeeting = meeting
            panel.attachNotes(view)
        } else {
            showInWindow(meeting, view)
        }
    }

    /// Call on every change of the recorder's phase.
    func activeMeetingChanged() {
        guard let shown = panelMeeting, let active = recorder.activeMeeting, active != shown,
              let view = views[shown] else { return }
        showInWindow(shown, view)
    }

    private func makeView(for meeting: MeetingFolder) throws -> MeetingTypedNotesView {
        MeetingTypedNotesView(session: try notes.typedNotes(for: meeting),
                              requestUpdate: { [weak notes] in notes?.updateSummary(meeting) })
    }

    private func showInWindow(_ meeting: MeetingFolder, _ view: MeetingTypedNotesView) {
        if let window = windows[meeting] {
            window.show()
            return
        }
        if panelMeeting == meeting {
            panelMeeting = nil
            panel.detachNotes()
        }
        let window = makeWindow(view)
        window.onClose = { [weak self] in
            self?.windows.removeValue(forKey: meeting)
            self?.release(meeting)
        }
        windows[meeting] = window
        window.show()
    }

    private func closePanelNotes() {
        guard let meeting = panelMeeting else { return }
        panelMeeting = nil
        panel.detachNotes()
        release(meeting)
    }

    private func release(_ meeting: MeetingFolder) {
        if notes.closeTypedNotes(for: meeting) { views.removeValue(forKey: meeting) }
    }
}
