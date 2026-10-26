import XCTest
@testable import KuKa

final class AudioTimelineTests: XCTestCase {
    func testABufferOnTimeNeedsNoSilence() {
        XCTAssertEqual(AudioTimeline.silenceFrames(written: 16_000, bufferStart: 1.0, sampleRate: 16_000), 0)
    }

    func testJitterWithinTheToleranceNeedsNoSilence() {
        XCTAssertEqual(AudioTimeline.silenceFrames(written: 16_000, bufferStart: 1.04, sampleRate: 16_000), 0)
    }

    func testAGapIsFilledUpToTheBufferStart() {
        XCTAssertEqual(AudioTimeline.silenceFrames(written: 16_000, bufferStart: 2.5, sampleRate: 16_000), 24_000)
    }

    func testAnEarlyBufferIsNotTrimmed() {
        XCTAssertEqual(AudioTimeline.silenceFrames(written: 20_000, bufferStart: 1.0, sampleRate: 16_000), 0)
    }
}
