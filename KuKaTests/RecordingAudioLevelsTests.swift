import XCTest
@testable import KuKa

final class RecordingAudioLevelsTests: XCTestCase {
    func testTracksHaveIndependentLevelsAndExpireIndependently() {
        var meter = RecordingAudioMeter()
        XCTAssertEqual(meter.levels(at: 10), RecordingAudioLevels(microphone: 0, system: 0))

        meter.record(rms: 0.1, for: .microphone, at: 10)
        meter.record(rms: 0.01, for: .system, at: 10.25)

        XCTAssertEqual(meter.levels(at: 10.49).microphone, 2.0 / 3, accuracy: 0.000001)
        XCTAssertEqual(meter.levels(at: 10.49).system, 1.0 / 3, accuracy: 0.000001)
        XCTAssertEqual(meter.levels(at: 10.5).microphone, 0)
        XCTAssertEqual(meter.levels(at: 10.5).system, 1.0 / 3, accuracy: 0.000001)
        XCTAssertEqual(meter.levels(at: 10.75), RecordingAudioLevels(microphone: 0, system: 0))
    }

    func testSilenceAndFullScaleStayBoundedAndAStaleTrackCanRecover() {
        var meter = RecordingAudioMeter()
        meter.record(rms: 0, for: .microphone, at: 10)
        meter.record(rms: 1, for: .system, at: 10)
        XCTAssertEqual(meter.levels(at: 10), RecordingAudioLevels(microphone: 0, system: 1))
        XCTAssertEqual(meter.levels(at: 11), RecordingAudioLevels(microphone: 0, system: 0))

        meter.record(rms: 0.0001, for: .microphone, at: 11)
        meter.record(rms: 2, for: .system, at: 11)
        XCTAssertEqual(meter.levels(at: 11), RecordingAudioLevels(microphone: 0, system: 1))

        meter.record(rms: 0.1, for: .microphone, at: 12)
        XCTAssertEqual(meter.levels(at: 12).microphone, 2.0 / 3, accuracy: 0.000001)
        XCTAssertEqual(meter.levels(at: 12).system, 0)
    }
}
