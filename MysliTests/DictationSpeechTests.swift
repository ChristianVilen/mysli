import XCTest
@testable import Mysli

@MainActor
final class DictationSpeechTests: XCTestCase {
    func testNoSpeechNeedsAcousticEvidenceAndWordsButKeepsASpokenThankYou() async throws {
        let model = SampleSpeechFake()
        let speech = DictationSpeech(load: { model })
        let session = try await speech.prepare()
        let rows: [(Double, Float, String, Bool)] = [
            (0, 0, "Thank you.", false),
            (0.119, 0.1, "Thank you.", false),
            (0.12, 0.009, "Hello", false),
            (0.12, 0.01, "Thank you.", true),
            (0.2, 0.1, " ... ", false),
            (0.2, 0.1, "42", true),
        ]
        for (seconds, peak, text, expected) in rows {
            model.text = text
            let result = try await session.transcribe(DictationAudio(samples: [0.2], evidence: .init(voicedSeconds: seconds, peak: peak)))
            switch result {
            case .noSpeech: XCTAssertFalse(expected, text)
            case .text(let value): XCTAssertTrue(expected, text); XCTAssertEqual(value, text)
            }
        }
        XCTAssertEqual(model.inputs, [[0.2], [0.2], [0.2]])
        let empty = try await session.transcribe(DictationAudio(samples: [], evidence: .init(voicedSeconds: 1, peak: 1)))
        if case .text = empty { XCTFail("Empty audio produced speech") }
        session.release()
        session.release()
    }

    func testReleaseDoesNotInvalidateAnInFlightTranscription() async throws {
        let model = SampleSpeechFake()
        let gate = DictationTestGate<String>()
        model.gate = gate
        let session = try await DictationSpeech(load: { model }).prepare()
        let task = Task { try await session.transcribe(DictationAudio(samples: [0.2], evidence: .init(voicedSeconds: 1, peak: 1))) }
        await gate.waitUntilEntered()
        session.release()
        gate.resume("Keep these words")
        if case .text(let text) = try await task.value { XCTAssertEqual(text, "Keep these words") }
        else { XCTFail("Speech was lost") }
    }
}

@MainActor
private final class SampleSpeechFake: SampleTranscriptionSession {
    var text = "Thank you."
    var inputs: [[Float]] = []
    var gate: DictationTestGate<String>?
    func transcribe(samples: [Float]) async throws -> String {
        inputs.append(samples)
        if let gate { return await gate.value() }
        return text
    }
}
