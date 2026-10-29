import AppKit

enum MeetingPanelCopy {
    struct Button: Equatable {
        /// Nil for a button that shows only its symbol.
        let title: String?
        /// For VoiceOver.
        let label: String
        let tooltip: String
    }

    /// Nil while recording: the mark and the time say it.
    static func word(for status: MeetingControls.Status) -> String? {
        switch status {
        case .starting: return "Starting…"
        case .recording: return nil
        case .paused: return "Paused"
        case .saved: return "Recording saved"
        case .interrupted: return "Recording stopped"
        }
    }

    static func timeLabel(_ recorded: TimeInterval) -> String {
        "Recorded time \(RecordedTime.format(recorded))"
    }

    static func note(for status: MeetingControls.Status) -> String? {
        switch status {
        case .saved:
            return "Ku-Ka is making the transcript and notes. You get a notification when they are ready."
        case .interrupted(let reason):
            return interruptedNote(reason)
        case .starting, .recording, .paused:
            return nil
        }
    }

    /// Also the body of the Recording Stopped notification.
    static func interruptedNote(_ reason: String) -> String {
        "\(reason) Ku-Ka makes notes from what it recorded. To record the rest, choose Start Recording Meeting."
    }

    /// Paused shows Resume in text, so the state does not rest on the symbol alone.
    static func pauseButton(isPaused: Bool) -> Button {
        isPaused
            ? Button(title: "Resume", label: "Resume recording", tooltip: "Resume recording")
            : Button(title: nil, label: "Pause recording", tooltip: "Pause recording. Nothing is recorded until you resume.")
    }

    static let stopButton = Button(title: nil, label: "Stop recording", tooltip: "Stop recording and make notes")
    static let closeButton = Button(title: nil, label: "Close", tooltip: "Close")

    static func transcriptButton(isOpen: Bool) -> Button {
        let label = isOpen ? "Hide live transcript" : "Show live transcript"
        return Button(title: nil, label: label, tooltip: label)
    }

    static let hideButton = Button(
        title: "Hide panel", label: "Hide panel",
        tooltip: "Recording continues. Choose Show Meeting Controls in the Ku-Ka menu to bring the panel back.")

    static let transcriptTitle = "Live transcript"
    static let draftNote = "Draft until you stop"
    static let draftTooltip = "Rough text while you record. Ku-Ka writes the full transcript after you stop."
    static let transcriptLabel = "Live transcript draft"
    static let heightGripTooltip = "Drag to change the height"

    /// Nil while text can come.
    static func message(for status: LiveTranscript.Status) -> (title: String, body: String)? {
        switch status {
        case .preparing:
            return ("Preparing live transcript", "Recording has started and is not affected.")
        case .live:
            return nil
        case .unavailable(let reason):
            return ("No live transcript for this meeting",
                    "\(reason) Ku-Ka still records both sides and writes the full transcript after you stop.")
        case .failed(let reason):
            return ("Live transcript stopped",
                    "\(reason) Recording continues, and Ku-Ka writes the full transcript after you stop.")
        }
    }

    static func behindChip(_ behind: TimeInterval?) -> String? {
        behind.map { "\(Int($0.rounded())) s behind" }
    }

    static func speech(_ text: String, isFinal: Bool) -> String {
        isFinal ? text : "\(text)…"
    }

    static func pauseRow(at recorded: TimeInterval, duration: TimeInterval?) -> String {
        let at = "Paused at \(RecordedTime.format(recorded))"
        return duration.map { "\(at) for \(RecordedTime.format($0))" } ?? at
    }

    static func returnToLive(newRows: Int) -> String {
        newRows > 0 ? "Return to live · \(newRows) new" : "Return to live"
    }

    /// Only a change of kind is announced, so a time tick or a transcript row never is. Nil
    /// stands for a hidden panel: hiding it and showing it again change nothing, but the end of
    /// a recording is announced even when the panel was hidden.
    static func announcement(from old: MeetingControls.Status?, to new: MeetingControls.Status?)
        -> (text: String, priority: NSAccessibilityPriorityLevel)? {
        switch (old, new) {
        case (.starting?, .recording?): return ("Recording started.", .medium)
        case (.recording?, .paused?): return ("Recording paused. Nothing is recorded until you resume.", .medium)
        case (.paused?, .recording?): return ("Recording resumed.", .medium)
        case (.saved?, .saved?), (.interrupted?, .interrupted?): return nil
        case (_, .saved?): return ("Recording saved. Ku-Ka is making the notes.", .medium)
        case (_, .interrupted(let reason)?): return ("Recording stopped. \(reason)", .high)
        default: return nil
        }
    }
}
