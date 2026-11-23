#if DEBUG
import AppKit
import SwiftUI

#Preview("Meeting controls · Starting", traits: .fixedLayout(width: 270, height: 42)) {
    MeetingPreviews.controls(.starting)
}

#Preview("Meeting controls · Recording", traits: .fixedLayout(width: 258, height: 42)) {
    MeetingPreviews.controls(.recording, recordedTime: 784)
}

#Preview("Meeting controls · Paused", traits: .fixedLayout(width: 326, height: 42)) {
    MeetingPreviews.controls(.paused, recordedTime: 784, reduceTransparency: true)
}

#Preview("Meeting controls · Saved", traits: .fixedLayout(width: 300, height: 110)) {
    MeetingPreviews.controls(.saved)
}

#Preview("Meeting controls · Interrupted", traits: .fixedLayout(width: 300, height: 130)) {
    MeetingPreviews.controls(.interrupted(reason: "The display disconnected."))
}

#Preview("Live transcript · Running behind", traits: .fixedLayout(width: 380, height: 322)) {
    MeetingPreviews.controls(.recording, recordedTime: 784, transcript: MeetingPreviews.transcript)
}

#Preview("Live transcript · Unavailable", traits: .fixedLayout(width: 380, height: 322)) {
    MeetingPreviews.controls(.recording, recordedTime: 784, transcript: LivePreview(
        status: .unavailable("The speech model for this language is missing."),
        rows: [], behind: nil))
}

#Preview("Live transcript and meeting notes", traits: .fixedLayout(width: 460, height: 422)) {
    MeetingPreviews.controlsWithNotes(recording: true)
}

#Preview("Meeting controls · Notes after Stop", traits: .fixedLayout(width: 460, height: 422)) {
    MeetingPreviews.controlsWithNotes(recording: false)
}

#Preview("Saved meeting notes", traits: .fixedLayout(width: 600, height: 500)) {
    MeetingPreviews.savedNotes()
}

#Preview("Recording audio meter", traits: .fixedLayout(width: 260, height: 62)) {
    MeetingPreviews.audioMeter(.init(microphone: 0.7, system: 0.35))
}

#Preview("Recording audio meter · Silent", traits: .fixedLayout(width: 260, height: 62)) {
    MeetingPreviews.audioMeter(.silent)
}

#Preview("Check Words · Question") {
    MeetingPreviews.wordReview(.question(.init(
        meetingTitle: "Release planning", number: 2, count: 3,
        heard: "my key", place: "Them at 00:12:41",
        quote: .init("Then my key will send the checklist.", around: "my key"),
        reason: "This may be a product name.", suggestion: "Maikki", isOrdinary: true)))
}

#Preview("Check Words · Finished") {
    MeetingPreviews.wordReview(.finished(.init(
        meetingTitle: "Release planning", canUpdateNotes: true, isUpdating: false, otherMeetings: 1)))
}

@MainActor
private enum MeetingPreviews {
    static let transcript = LivePreview(status: .live, rows: [
        LiveRow(at: 749, content: .speech(.me, text: "Can we check what needs to go in the release notes?", isFinal: true)),
        LiveRow(at: 755, content: .speech(.them, text: "Yes. Include the keyboard shortcut and the new export format.", isFinal: true)),
        LiveRow(at: 760, content: .pause(duration: 24)),
        LiveRow(at: 762, content: .speech(.me, text: "I'll add both to the draft.", isFinal: true)),
        LiveRow(at: 771, content: .speech(.them, text: "Then Maikki will send the checklist…", isFinal: false)),
    ], behind: 6)

    static func controls(_ status: MeetingControls.Status, recordedTime: TimeInterval? = nil,
                         transcript: LivePreview? = nil, reduceTransparency: Bool = false,
                         notes: (MeetingTypedNotesView, MeetingPreviewDirectory)? = nil) -> NSViewController {
        let defaults = AppKitPreview.defaults()
        let services = InertMeetingServices()
        let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let recorder = MeetingRecorder(
            permissions: PermissionsManager(
                isAccessibilityTrusted: { false }, hasScreenCaptureAccess: { false },
                microphoneAccess: { .denied }, inputMonitoringAccess: { false },
                requestMicrophoneAccess: { false }, openURL: { _ in false },
                showAccessibilityPrompt: {}, defaults: defaults),
            root: { isolatedURL() }, capture: services, liveTranscriber: services,
            teamsSpeakerObserver: services, notifier: services,
            alertStartFailure: { _, _ in false }, closeSavedNoticeLater: { _ in })
        let panel = MeetingControlsPanel(
            recorder: recorder, settings: Settings(defaults: defaults, loginItem: PreviewLoginItem()),
            screens: PreviewScreens(all: [ScreenGeometry(frame: screenFrame, visibleFrame: screenFrame)]), announce: { _, _ in },
            displayOptions: { (true, reduceTransparency) }, mouseLocation: { .zero })
        let view = panel.previewContent(status: status, recordedTime: recordedTime, transcript: transcript, notes: notes?.0)
        var owners: [AnyObject] = [panel]
        if let notes { owners.append(notes.1) }
        return AppKitPreview.host(view, retaining: owners as NSArray)
    }

    static func controlsWithNotes(recording: Bool) -> NSViewController {
        do {
            let (session, directory) = try notesSession(completed: false)
            session.context = { recording ? (.recording, .idle) : (.idle, .processing) }
            session.noteTime = { recording ? .recording(784) : .afterRecording }
            let notes = MeetingTypedNotesView(session: session, requestUpdate: {}, confirmReload: { _ in false })
            notes.showSampleNotesOnly()
            return controls(recording ? .recording : .saved, recordedTime: 784,
                            transcript: recording ? transcript : nil, notes: (notes, directory))
        } catch {
            return unavailable(error)
        }
    }

    static func savedNotes() -> NSViewController {
        do {
            let (session, directory) = try notesSession(completed: true)
            let notes = MeetingTypedNotesView(
                session: session, requestUpdate: {
                    let snapshot = session.savedText
                    session.context = { (.idle, .updated(snapshot: snapshot)) }
                }, confirmReload: { _ in false })
            notes.showSampleNotesOnly()
            let host = MeetingTypedNotesHost(view: notes, activation: inertActivation(), present: { _ in })
            guard let window = host.window, let view = window.contentView else {
                return unavailable(MeetingStepError("The notes window has no content."))
            }
            window.contentView = nil
            return AppKitPreview.host(view, retaining: [host, directory] as NSArray)
        } catch {
            return unavailable(error)
        }
    }

    static func audioMeter(_ levels: RecordingAudioLevels) -> NSViewController {
        let view = RecordingAudioMeterView()
        view.show(levels)
        return AppKitPreview.host(view)
    }

    static func wordReview(_ page: WordReviewScreen.Page) -> NSViewController {
        let root = isolatedURL()
        let controller = WordReviewController(
            root: { root },
            knownWords: KnownWordsFile(url: { root.appending(path: "known-words.md") },
                                       lockURL: root.appending(path: "known-words.lock")),
            isOrdinary: { _ in false }, requestUpdate: { _ in }, openURL: { _ in })
        let host = WordReviewWindowController(controller: controller, activation: inertActivation())
        let view = host.previewContent(WordReviewScreen(page: page, error: nil))
        return AppKitPreview.host(view, retaining: host)
    }

    private static func notesSession(completed: Bool) throws -> (MeetingTypedNotesSession, MeetingPreviewDirectory) {
        let directory = try MeetingPreviewDirectory(url: isolatedURL())
        let meeting = try MeetingFolder.create(in: directory.url, startingAt: Date(timeIntervalSince1970: 1_790_000_000))
        try meeting.saveDisplayTitle("Release planning")
        var entries = [
            MeetingNoteEntry(time: .recording(755), text: "Mention the keyboard shortcut and export format in the release notes."),
            MeetingNoteEntry(time: .recording(771), text: "Maikki will send the release checklist."),
        ]
        if completed {
            let image = NSImage(size: NSSize(width: 260, height: 100), flipped: false) { rect in
                NSColor.systemIndigo.withAlphaComponent(0.15).setFill()
                rect.fill()
                ("Release checklist" as NSString).draw(at: NSPoint(x: 16, y: 60), withAttributes: [
                    .font: NSFont.boldSystemFont(ofSize: 16), .foregroundColor: NSColor.labelColor,
                ])
                ("Review notes   ·   Check export   ·   Publish" as NSString).draw(at: NSPoint(x: 16, y: 32), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor,
                ])
                return true
            }
            if let imageData = image.tiffRepresentation {
                let screenshot = try MeetingScreenshot.decode(imageData)
                let attachment = try MeetingScreenshotStore(meeting: meeting).write(screenshot)
                entries.append(MeetingNoteEntry(time: .afterRecording, text: "Checklist from the call.", attachments: [attachment]))
            }
            try meeting.write("# Transcript", to: .transcript)
            try meeting.write("# Release planning", to: .summary)
        }
        try meeting.write(MeetingNoteDocument.render(entries), to: .notes)
        return (try MeetingTypedNotesSession(meeting: meeting), directory)
    }

    private static func isolatedURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "mysli-meeting-preview-\(UUID().uuidString)")
    }

    private static func inertActivation() -> OrdinaryWindowActivation {
        OrdinaryWindowActivation(setPolicy: { _ in }, activateApp: {}, nextTurn: { _ in })
    }

    private static func unavailable(_ error: Error) -> NSViewController {
        let label = NSTextField(wrappingLabelWithString: error.localizedDescription)
        return AppKitPreview.host(label, size: NSSize(width: 360, height: 80))
    }
}

private final class MeetingPreviewDirectory {
    let url: URL

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        self.url = url
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}

private struct InertMeetingServices: MeetingAudioCapturing, LiveTranscribing, TeamsSpeakerObserving, Notifying {
    func start(into meeting: MeetingFolder, clock: RecordingClock,
               onInterrupted: @escaping @MainActor (String) -> Void) async throws -> ActiveRecording {
        throw MeetingStepError("Recording is unavailable in previews.")
    }

    func updates(locale: Locale, audio: [MeetingTrack: AsyncStream<WrittenAudio>]) -> AsyncStream<LiveUpdate> {
        AsyncStream { $0.finish() }
    }

    func observations() -> AsyncStream<TeamsSpeakerObservation> {
        AsyncStream { $0.finish() }
    }

    func requestPermission() {}
    func post(title: String, body: String, onClick: NotificationClick?) {}
}
#endif
