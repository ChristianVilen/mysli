import XCTest
@testable import KuKa

final class ScrollTransformTests: XCTestCase {
    private func makeEvent(line: Int32, continuous: Bool = false) -> CGEvent {
        let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: line,
            wheel2: 0,
            wheel3: 0
        )!
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
        return event
    }

    func testInvertNegatesAllAxis1Deltas() {
        let event = makeEvent(line: 3)
        let originalPoint = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let originalFixed = event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1)

        let settings = ScrollTransformSettings(invert: true, disableAcceleration: false, linesPerTick: 3)
        _ = ScrollTransform.apply(to: event, settings: settings)

        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), -3)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), -originalPoint)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1), -originalFixed)
    }

    func testContinuousEventPassesThroughUnchanged() {
        let event = makeEvent(line: 3, continuous: true)
        let originalLine = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)

        let settings = ScrollTransformSettings(invert: true, disableAcceleration: true, linesPerTick: 5)
        _ = ScrollTransform.apply(to: event, settings: settings)

        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), originalLine)
    }

    func testDisableAccelerationFlattensToLinesPerTick() {
        let event = makeEvent(line: -2)

        let settings = ScrollTransformSettings(invert: false, disableAcceleration: true, linesPerTick: 5)
        _ = ScrollTransform.apply(to: event, settings: settings)

        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), -5)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), -50)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1), Int64(-50) << 16)
    }

    func testDisableAccelerationWithInvertFlipsSign() {
        let event = makeEvent(line: -2)

        let settings = ScrollTransformSettings(invert: true, disableAcceleration: true, linesPerTick: 5)
        _ = ScrollTransform.apply(to: event, settings: settings)

        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 5)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 50)
    }

    func testZeroDeltaPassesThrough() {
        let event = makeEvent(line: 0)

        let settings = ScrollTransformSettings(invert: true, disableAcceleration: true, linesPerTick: 5)
        _ = ScrollTransform.apply(to: event, settings: settings)

        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 0)
    }

    func testAllOffIsNoOp() {
        let event = makeEvent(line: 3)
        let originalLine = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let originalPoint = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)

        let settings = ScrollTransformSettings(invert: false, disableAcceleration: false, linesPerTick: 3)
        _ = ScrollTransform.apply(to: event, settings: settings)

        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), originalLine)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), originalPoint)
    }

    func testHorizontalAxisUntouched() {
        let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 3,
            wheel2: 4,
            wheel3: 0
        )!
        let originalAxis2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)

        let settings = ScrollTransformSettings(invert: true, disableAcceleration: true, linesPerTick: 5)
        _ = ScrollTransform.apply(to: event, settings: settings)

        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis2), originalAxis2)
    }
}
