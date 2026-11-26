import XCTest
@testable import Mysli

@MainActor
final class EarlyTranscriptWorkerTests: XCTestCase {
    private var meeting: MeetingFolder!
    private var whisper: FakeEarlyWhisper!
    private var ticks: FakeTicks!
    /// The length of each track file, by file name.
    private var lengths: [String: Int64] = [:]

    override func setUpWithError() throws {
        meeting = try MeetingFolder.create(in: try makeTemporaryDirectory(), startingAt: localDate(2026, 10, 23, 14, 2))
        whisper = FakeEarlyWhisper()
        ticks = FakeTicks()
        lengths = ["me.caf": frames(240), "them.caf": frames(209)]
    }

    private func makeWorker(for meeting: MeetingFolder) -> EarlyTranscriptWorker {
        EarlyTranscriptWorker(meeting: meeting, transcriber: whisper, locale: Locale(identifier: "en-US"),
                              frameCount: { [unowned self] in try XCTUnwrap(lengths[$0.lastPathComponent]) },
                              wait: { [unowned self] in try await ticks.wait() })
    }

    /// A track is due with 210 s of audio after what its early transcript covers.
    func testEachPassExtendsWhatTheLastOneReturnedAndSavesIt() async throws {
        let first = early(covered: 205, [segment(10, 20, "One")])
        let second = early(covered: 330, [segment(10, 20, "One"), segment(300, 310, "Two")])
        whisper.results = [first, second]
        let worker = makeWorker(for: meeting)
        worker.start()
        ticks.tick()
        await waitUntil { meeting.earlyTranscript(.microphone) != nil }

        XCTAssertEqual(meeting.earlyTranscript(.microphone), first)

        lengths["me.caf"] = frames(415)
        ticks.tick()
        await waitUntil { meeting.earlyTranscript(.microphone) == second }

        XCTAssertEqual(whisper.calls, ["me.caf from 0", "me.caf from 3280000"])
        XCTAssertNil(meeting.earlyTranscript(.system))
        worker.cancel()
        await worker.waitUntilEnded()
    }

    func testWithoutAReadyWhisperModelARecordingGetsNoEarlyText() async throws {
        let rows: [(name: String, prepare: (FakeEarlyWhisper) -> Void)] = [
            ("model not installed", { $0.modelIsMissing = true }),
            ("language not supported", { $0.unavailable = MeetingStepError("Whisper does not support eo.") }),
            ("model does not load", { $0.loadError = MeetingStepError("The model files are damaged.") }),
        ]
        for row in rows {
            whisper = FakeEarlyWhisper()
            row.prepare(whisper)
            ticks = FakeTicks()
            ticks.tick()
            let worker = makeWorker(for: meeting)

            worker.start()
            await worker.waitUntilEnded()

            XCTAssertNil(meeting.earlyTranscript(.microphone), row.name)
            XCTAssertEqual(whisper.calls, [], row.name)
        }
    }

    func testStopThrowsAwayThePassInFlightSoNothingIsWrittenAfterIt() async throws {
        let release = AudioTestSignal()
        whisper.passRelease = release
        whisper.results = [early(covered: 205, [segment(10, 20, "One")])]
        var worker: EarlyTranscriptWorker?
        var ended: [MeetingFolder] = []
        let root = try makeTemporaryDirectory()
        let recorder = MeetingRecorder(
            permissions: PermissionsManager(isAccessibilityTrusted: { true }, hasScreenCaptureAccess: { true },
                                            microphoneAccess: { .granted }),
            root: { root },
            capture: FakeMeetingAudioCapture(), liveTranscriber: FakeLiveTranscriber(), notifier: FakeNotifier(),
            closeSavedNoticeLater: { _ in },
            earlyTranscript: { [unowned self] meeting, _ in
                let made = makeWorker(for: meeting)
                worker = made
                return made
            })
        recorder.onEnded = { ended.append($0.folder) }
        _ = await recorder.startRecording()
        let recording = try XCTUnwrap(recorder.activeMeeting)
        ticks.tick()
        await whisper.passStarted.value()

        recorder.stopRecording()
        await release.send()
        await worker?.waitUntilEnded()

        XCTAssertEqual(ended, [recording])
        XCTAssertEqual(whisper.calls, ["me.caf from 0"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: recording.earlyTranscriptURL(.microphone).path))
    }

    private func early(covered seconds: Double, _ segments: [TranscriptSegment]) -> EarlyTranscript {
        EarlyTranscript(source: EarlyTranscriptSource(transcriber: "Whisper", language: "en"), covered: frames(seconds),
                        segments: segments)
    }

    private func segment(_ start: Double, _ end: Double, _ text: String) -> TranscriptSegment {
        TranscriptSegment(start: start, end: end, text: text)
    }
}

/// `extend` returns `results` in order. While `passRelease` is set, it waits for it after `passStarted`.
private final class FakeEarlyWhisper: EarlyTranscribing {
    var modelIsMissing = false
    /// Thrown by `needsDownload`, as for a language that Whisper does not support.
    var unavailable: Error?
    var loadError: Error?
    var results: [EarlyTranscript] = []
    let passStarted = AudioTestSignal()
    var passRelease: AudioTestSignal?
    /// Each `extend`: the file and the frame that the given early transcript covers.
    private(set) var calls: [String] = []

    func needsDownload(for locale: Locale) async throws -> Bool {
        if let unavailable { throw unavailable }
        return modelIsMissing
    }

    func loadEarly(for locale: Locale) async throws -> any EarlyTranscriptionSession {
        if let loadError { throw loadError }
        return Session(whisper: self)
    }

    private struct Session: EarlyTranscriptionSession {
        let whisper: FakeEarlyWhisper

        func extend(_ early: EarlyTranscript?, of audio: URL) async throws -> EarlyTranscript {
            whisper.calls.append("\(audio.lastPathComponent) from \(early?.covered ?? 0)")
            await whisper.passStarted.send()
            if let release = whisper.passRelease { await release.value() }
            return whisper.results.removeFirst()
        }
    }
}

/// Each `wait()` returns at a `tick()`, one sent before it included, or throws when its task is cancelled.
@MainActor
private final class FakeTicks {
    private var pending = 0
    private var waiter: CheckedContinuation<Void, Error>?

    func tick() {
        if let waiter {
            self.waiter = nil
            waiter.resume()
        } else {
            pending += 1
        }
    }

    func wait() async throws {
        if pending > 0 {
            pending -= 1
            return
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { waiter = $0 }
        } onCancel: {
            Task { @MainActor in self.cancelWaiter() }
        }
    }

    private func cancelWaiter() {
        let cancelled = waiter
        waiter = nil
        cancelled?.resume(throwing: CancellationError())
    }
}

private func frames(_ seconds: Double) -> Int64 {
    Int64((seconds * 16_000).rounded())
}
