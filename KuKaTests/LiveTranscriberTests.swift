import AVFAudio
import CoreMedia
import Speech
import XCTest
@testable import KuKa

final class LiveTranscriberTests: XCTestCase {
    func testAVolatileResultGivesFileSecondsAndPlainText() {
        let result = LiveResult(track: .system, range: CMTimeRange(start: time(1.5), end: time(4)),
                                finalizationTime: time(1.5), text: words(("So", 1.6, 1.8), ("the", 1.8, 2), ("plan", 2, 2.4)))

        XCTAssertEqual(result, LiveResult(track: .system, start: 1.5, end: 4,
                                          phrases: [TranscriptSegment(start: 1.6, end: 2.4, text: "So the plan")],
                                          isFinal: false, finalizedThrough: 1.5))
    }

    func testEachSentenceIsAPhraseFromItsFirstWordToItsLast() {
        let text = words(("Are", 1, 1.2), ("we", 1.2, 1.4), ("ready?", 1.4, 1.8), ("Yes,", 1.9, 2.1), ("go!", 2.1, 2.4),
                         ("Okay.", 2.5, 2.9), ("Then", 3, 3.2))

        let result = LiveResult(track: .microphone, range: CMTimeRange(start: time(0.8), end: time(3.5)),
                                finalizationTime: time(0.8), text: text)

        XCTAssertEqual(result.phrases, [TranscriptSegment(start: 1, end: 1.8, text: "Are we ready?"),
                                        TranscriptSegment(start: 1.9, end: 2.4, text: "Yes, go!"),
                                        TranscriptSegment(start: 2.5, end: 2.9, text: "Okay."),
                                        TranscriptSegment(start: 3, end: 3.2, text: "Then")])
    }

    func testAPauseOfAtLeastSevenTenthsOfASecondStartsAPhraseAndAShorterOneDoesNot() {
        // 0.7 s from "wait" to "No", 0.6 s from "we" to "ship".
        let text = words(("So", 1, 1.2), ("we", 1.2, 1.4), ("wait", 1.4, 2), ("No", 2.7, 2.9), ("we", 2.9, 3),
                         ("ship", 3.6, 4))

        let result = LiveResult(track: .microphone, range: CMTimeRange(start: time(1), end: time(4.2)),
                                finalizationTime: time(1), text: text)

        XCTAssertEqual(result.phrases, [TranscriptSegment(start: 1, end: 2, text: "So we wait"),
                                        TranscriptSegment(start: 2.7, end: 4, text: "No we ship")])
    }

    func testTextWithoutWordTimesIsOnePhraseOverTheResultsRange() {
        let result = LiveResult(track: .microphone, range: CMTimeRange(start: time(1.5), end: time(4)),
                                finalizationTime: time(4), text: AttributedString("Ship it. Today?"))

        XCTAssertEqual(result.phrases, [TranscriptSegment(start: 1.5, end: 4, text: "Ship it. Today?")])
    }

    func testAResultIsFinalOnceTheFinalizationTimeReachesItsEnd() {
        let range = CMTimeRange(start: time(1.5), end: time(4))

        let atEnd = LiveResult(track: .microphone, range: range, finalizationTime: time(4),
                               text: AttributedString("Ship it."))
        // The analyzer's own timescale can differ from the input's.
        let past = LiveResult(track: .microphone, range: range,
                              finalizationTime: CMTime(seconds: 4.25, preferredTimescale: 1_000_000_000),
                              text: AttributedString("Ship it."))
        let before = LiveResult(track: .microphone, range: range,
                                finalizationTime: CMTime(value: 3_999_999, timescale: 1_000_000),
                                text: AttributedString("Ship it."))

        XCTAssertTrue(atEnd.isFinal)
        XCTAssertTrue(past.isFinal)
        XCTAssertEqual(past.finalizedThrough, 4.25)
        XCTAssertFalse(before.isFinal)
    }

    func testABufferGoesInAtItsExactFrame() throws {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: AudioTrackWriter.fileFormat, frameCapacity: 320))
        // 4.02 s and 4.06 s: one frame early would overlap the buffer before, and the analyzer
        // would stop with "Audio input timestamp overlaps or precedes prior audio input".
        for frame in [64_320, 64_960] as [CMTimeValue] {
            let audio = WrittenAudio(buffer: buffer, filePosition: Double(frame) / 16_000, rms: 0)
            XCTAssertEqual(audio.startTime, CMTime(value: frame, timescale: 16_000))
        }
    }

    private func time(_ seconds: Double) -> CMTime {
        CMTime(value: CMTimeValue((seconds * 16_000).rounded()), timescale: 16_000)
    }

    /// Each word with its audio time, and an untimed space between words.
    private func words(_ words: (text: String, start: Double, end: Double)...) -> AttributedString {
        var text = AttributedString()
        for (index, word) in words.enumerated() {
            if index > 0 { text += AttributedString(" ") }
            var run = AttributedString(word.text)
            run.audioTimeRange = CMTimeRange(start: time(word.start), end: time(word.end))
            text += run
        }
        return text
    }
}
