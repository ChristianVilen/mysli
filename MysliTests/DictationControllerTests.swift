import XCTest
@testable import Mysli

@MainActor
final class DictationControllerTests: XCTestCase {
    func testEscapeRegistrationFailurePreventsCaptureAndLostKeysCancelActiveWork() async {
        let f = DictationFixture()
        f.controller.setEnabled(true)
        await f.waitFor(.idle)
        f.keys.cancellationFails = true
        f.controller.receive(.pressed)
        XCTAssertEqual(f.controller.presentation, .error)
        XCTAssertTrue(f.recorder.captures.isEmpty)
        f.keys.cancellationFails = false
        f.clock.advance(to: 2)
        f.controller.receive(.pressed)
        f.controller.receive(.unavailable)
        XCTAssertEqual(f.controller.presentation, .error)
        XCTAssertEqual(f.recorder.captures.map(\.cancelled), [true])
        f.controller.shutdown()
    }
    func testCancellationOnPolishPresentationStopsThePolishRequest() async {
        let f = DictationFixture()
        await f.enable()
        f.speech.session.result = .text("cancelled")
        let cancelled = DictationTestGate<Void>()
        f.controller.onChange = {
            if f.controller.presentation == .polishing {
                f.controller.onChange = nil
                f.controller.cancel()
                cancelled.resume(())
            }
        }
        f.hold()
        await cancelled.value()
        f.speech.session.result = .text("kept")
        f.hold()
        await f.waitFor(.idle)
        XCTAssertEqual(f.polisher.requests.map(\.heardText), ["kept"])
        XCTAssertEqual(f.controller.lastDictation?.heardText, "kept")
        f.controller.shutdown()
    }

    func testShortHoldCancelsAndExactThresholdDeliversSelectedText() async {
        let f = DictationFixture()
        await f.enable()
        f.hold(0.299)
        XCTAssertEqual(f.controller.presentation, .idle)
        XCTAssertTrue(f.recorder.captures[0].cancelled)
        XCTAssertNil(f.speech.session.audioSamples)
        f.clock.now = 0
        f.hold()
        XCTAssertTrue(f.recorder.captures[1].sealed)
        await f.waitFor(.idle)
        XCTAssertEqual(f.paste.texts.map(\.value), ["polished"])
        XCTAssertEqual(f.controller.lastDictation?.heardText, "as heard")
        XCTAssertEqual(f.speech.session.audioSamples, [0.25])
        XCTAssertEqual(f.preparedHeard, ["as heard"])
        f.controller.shutdown()
    }

    func testDuplicateEventsAndHardLimitUseOneReleasePath() async {
        let f = DictationFixture()
        await f.enable()
        f.controller.receive(.pressed)
        f.controller.receive(.pressed)
        XCTAssertTrue(f.keys.cancellable)
        f.recorder.level?(0.6)
        f.clock.advance(to: 110)
        XCTAssertEqual(f.controller.presentation, .listening(level: 0.6, warning: true))
        f.clock.advance(to: 120)
        f.controller.receive(.released)
        f.controller.receive(.pressed)
        await f.waitFor(.idle)
        XCTAssertEqual(f.recorder.captures.count, 1)
        XCTAssertEqual(f.paste.texts.map(\.value), ["polished"])
        XCTAssertFalse(f.keys.cancellable)
        f.controller.shutdown()
    }

    func testReleaseSealsPendingStartupAndCancelSuppressesItsResult() async {
        let f = DictationFixture()
        await f.enable()
        let gate = DictationTestGate<DictationAudio>()
        f.recorder.next.gate = gate
        f.hold()
        XCTAssertTrue(f.recorder.captures[0].sealed)
        await gate.waitUntilEntered()
        f.controller.receive(.cancelled)
        XCTAssertTrue(f.recorder.captures[0].cancelled)
        XCTAssertEqual(f.controller.presentation, .idle)
        gate.resume(.init(samples: [1], evidence: .init(voicedSeconds: 1, peak: 1)))
        f.hold()
        await f.waitFor(.idle)
        XCTAssertEqual(f.paste.texts.map(\.value), ["polished"])
        f.controller.shutdown()
    }

    func testCancelledHoldIgnoresOldLevelAndTimerCallbacks() async {
        let f = DictationFixture()
        await f.enable()
        f.controller.receive(.pressed)
        let oldLevel = f.recorder.level
        let oldCallbacks = f.clock.callbacks.map(\.work)
        f.controller.receive(.cancelled)
        f.controller.receive(.released)
        f.controller.receive(.pressed)
        oldLevel?(1)
        oldCallbacks.forEach { $0() }
        XCTAssertEqual(f.controller.presentation, .listening(level: 0, warning: false))
        XCTAssertEqual(f.paste.texts, [])
        f.controller.shutdown()
    }

    func testNoSpeechSkipsContextPolishAndPaste() async {
        let f = DictationFixture()
        f.speech.session.result = .noSpeech
        await f.enable()
        f.hold()
        await f.waitFor(.idle)
        XCTAssertEqual(f.preparedHeard, [])
        XCTAssertTrue(f.polisher.requests.isEmpty)
        XCTAssertTrue(f.paste.texts.isEmpty)
        XCTAssertNil(f.controller.lastDictation)
        f.controller.shutdown()
    }

    func testUnavailablePolishUsesFallbackAndExpiryCannotEndNewHold() async {
        let f = DictationFixture()
        f.polisher.result = .unavailable
        await f.enable()
        f.hold()
        await f.waitFor(.unpolished)
        XCTAssertEqual(f.paste.texts.map(\.value), ["local"])
        let expiry = f.clock.callbacks.last!.work
        f.controller.receive(.pressed)
        expiry()
        XCTAssertEqual(f.controller.presentation, .listening(level: 0, warning: false))
        f.controller.cancel()
        f.hold()
        await f.waitFor(.unpolished)
        f.clock.advance(to: f.clock.now + 2)
        XCTAssertEqual(f.controller.presentation, .idle)
        f.controller.shutdown()
    }

    func testCancelAndDisableAtSpeechAndPolishBoundariesPreventDelivery() async {
        for disable in [false, true] {
            for atPolish in [false, true] {
                let f = DictationFixture()
                let speechGate = DictationTestGate<DictationSpeechResult>()
                let polishGate = DictationTestGate<DictationPolishResult>()
                if atPolish { f.polisher.gate = polishGate } else { f.speech.session.gate = speechGate }
                await f.enable()
                f.hold()
                if atPolish { await polishGate.waitUntilEntered() } else { await speechGate.waitUntilEntered() }
                if disable { f.controller.setEnabled(false) } else { f.controller.cancel() }
                if atPolish { polishGate.resume(.polished(PasteText("stale")!)) }
                else { speechGate.resume(.text("stale")) }
                f.speech.session.gate = nil
                f.polisher.gate = nil
                if disable { await f.enable() }
                f.hold()
                await f.waitFor(.idle)
                XCTAssertEqual(f.paste.texts.map(\.value), ["polished"])
                XCTAssertEqual(f.controller.lastDictation?.heardText, "as heard")
                f.controller.shutdown()
            }
        }
    }

    func testCancelAndDisableDuringContextPreparationKeepPreviousWords() async {
        for disable in [false, true] {
            let f = DictationFixture()
            await f.enable()
            f.hold()
            await f.waitFor(.idle)
            let last = f.controller.lastDictation
            let gate = DictationTestGate<Void>()
            f.textGate = gate
            f.speech.session.result = .text("cancelled words")
            f.hold()
            await gate.waitUntilEntered()
            f.controller.receive(.pressed)
            XCTAssertEqual(f.recorder.captures.count, 2)
            if disable { f.controller.setEnabled(false) } else { f.controller.cancel() }
            XCTAssertEqual(f.controller.lastDictation, last)
            gate.resume(())
            f.textGate = nil
            if disable { await f.enable() }
            f.speech.session.result = .noSpeech
            f.hold()
            await f.waitFor(.idle)
            XCTAssertEqual(f.controller.lastDictation, last)
            XCTAssertEqual(f.paste.texts.map(\.value), ["polished"])
            f.controller.shutdown()
        }
    }

    func testOldKeyCallbackCannotStartCaptureInNewEnable() async {
        let f = DictationFixture()
        await f.enable()
        let oldKeys = f.keys.receive
        f.controller.setEnabled(false)
        await f.enable()
        oldKeys?(.pressed)
        XCTAssertEqual(f.controller.presentation, .idle)
        XCTAssertTrue(f.recorder.captures.isEmpty)
        f.keys.receive?(.pressed)
        XCTAssertEqual(f.controller.presentation, .listening(level: 0, warning: false))
        XCTAssertEqual(f.recorder.captures.count, 1)
        f.controller.shutdown()
        XCTAssertTrue(f.recorder.captures[0].cancelled)
    }

    func testLatePreparationReleasesOnlyItsOwnResource() async {
        let f = DictationFixture()
        let gate = DictationTestGate<any DictationSpeechSession>()
        f.speech.gate = gate
        f.controller.setEnabled(true)
        await gate.waitUntilEntered()
        f.controller.setEnabled(false)
        XCTAssertNil(f.keys.receive)
        f.speech.gate = nil
        await f.enable()
        let stale = DictationTestSession()
        gate.resume(stale)
        f.hold()
        await f.waitFor(.idle)
        XCTAssertTrue(stale.released)
        XCTAssertFalse(f.speech.session.released)
        XCTAssertEqual(f.paste.texts.map(\.value), ["polished"])
        f.controller.shutdown()
        XCTAssertTrue(f.speech.session.released)
    }

    func testPolishReadinessDoesNotBlockLocalFallback() async {
        let f = DictationFixture()
        let gate = DictationTestGate<Void>()
        f.polisher.preparationGate = gate
        f.polisher.result = .unavailable
        await f.enable()
        await gate.waitUntilEntered()
        f.hold()
        await f.waitFor(.unpolished)
        XCTAssertEqual(f.paste.texts.map(\.value), ["local"])
        f.controller.shutdown()
        gate.resume(())
    }

    func testPasteFailureRetainsWordsForReplayAcrossDisable() async {
        let f = DictationFixture()
        f.paste.fails = true
        await f.enable()
        f.hold()
        await f.waitFor(.error)
        XCTAssertEqual(f.controller.lastDictation, LastDictation(heardText: "as heard", selectedText: PasteText("polished")!))
        f.controller.setEnabled(false)
        XCTAssertNotNil(f.controller.lastDictation)
        await f.enable()
        f.paste.fails = false
        f.controller.pasteLastAgain()
        await f.waitFor(.idle)
        XCTAssertEqual(f.paste.texts.map(\.value), ["polished", "polished"])
        XCTAssertEqual(f.preparedHeard, ["as heard"])
        f.controller.shutdown()
    }

    func testCancelledPasteCleanupBlocksReplayAndNewHoldAcrossEnable() async {
        let f = DictationFixture()
        let gate = DictationTestGate<Void>()
        f.paste.gate = gate
        await f.enable()
        f.hold()
        await gate.waitUntilEntered()
        f.controller.cancel()
        f.controller.pasteLastAgain()
        f.controller.receive(.pressed)
        XCTAssertEqual(f.recorder.captures.count, 1)
        f.controller.setEnabled(false)
        await f.enableSettling()
        f.controller.pasteLastAgain()
        f.controller.receive(.pressed)
        XCTAssertEqual(f.recorder.captures.count, 1)
        XCTAssertEqual(f.paste.texts.count, 1)
        f.paste.gate = nil
        gate.resume(())
        await f.waitFor(.idle)
        f.controller.pasteLastAgain()
        await f.waitFor(.idle)
        XCTAssertEqual(f.paste.texts.map(\.value), ["polished", "polished"])
        f.controller.shutdown()
    }

    func testKeyRegistrationFailureShowsErrorWithoutCaptureAndExpires() async {
        let f = DictationFixture()
        f.keys.fails = true
        f.controller.setEnabled(true)
        await f.waitFor(.error)
        f.controller.receive(.pressed)
        XCTAssertTrue(f.recorder.captures.isEmpty)
        f.clock.advance(to: 2)
        XCTAssertEqual(f.controller.presentation, .disabled)
        f.controller.shutdown()
    }
}
