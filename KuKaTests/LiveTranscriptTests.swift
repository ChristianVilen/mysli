import XCTest
@testable import KuKa

final class LiveTranscriptTests: XCTestCase {
    private var live = LiveTranscript()
    private var clock = RecordingClock(origin: HostTime(seconds: 100))

    private func apply(_ updates: LiveUpdate..., at now: TimeInterval = 100) {
        for update in updates { live.apply(update, now: HostTime(seconds: now), clock: clock) }
    }

    private var rows: [LiveRow] { live.preview(on: clock).rows }

    private func volatile(_ track: MeetingTrack, _ start: TimeInterval, _ end: TimeInterval, _ text: String,
                          finalizedThrough: TimeInterval = 0) -> LiveUpdate {
        .result(LiveResult(track: track, start: start, end: end, text: text, isFinal: false,
                           finalizedThrough: finalizedThrough))
    }

    private func final(_ track: MeetingTrack, _ start: TimeInterval, _ end: TimeInterval, _ text: String) -> LiveUpdate {
        .result(LiveResult(track: track, start: start, end: end, text: text, isFinal: true, finalizedThrough: end))
    }

    private func phrase(_ start: TimeInterval, _ end: TimeInterval, _ text: String) -> TranscriptSegment {
        TranscriptSegment(start: start, end: end, text: text)
    }

    private func speech(_ speaker: Speaker, _ at: TimeInterval, _ text: String, isFinal: Bool = true) -> LiveRow {
        LiveRow(at: at, content: .speech(speaker, text: text, isFinal: isFinal))
    }

    func testAVolatileResultShowsAsARowThatIsNotFinalAndANewerOneReplacesIt() {
        apply(volatile(.system, 1, 2, "Let's ship"))
        XCTAssertEqual(rows, [speech(.them, 1, "Let's ship", isFinal: false)])

        apply(volatile(.system, 1, 3, "Let's ship on Friday"))
        XCTAssertEqual(rows, [speech(.them, 1, "Let's ship on Friday", isFinal: false)])
    }

    func testAFinalResultReplacesTheVolatileTailItCoversAndKeepsATailAfterIt() {
        apply(volatile(.system, 1, 3, "Let's ship on Fri"), final(.system, 1, 3.2, "Let's ship on Friday."))
        XCTAssertEqual(rows, [speech(.them, 1, "Let's ship on Friday.")])

        apply(volatile(.system, 8, 9, "Next"), final(.system, 6, 7, "Any questions?"))
        XCTAssertEqual(rows, [speech(.them, 1, "Let's ship on Friday."), speech(.them, 6, "Any questions?"),
                              speech(.them, 8, "Next", isFinal: false)])
    }

    func testAVolatileTailThatALaterFinalizationTimePassesBecomesFinalAndStays() {
        apply(volatile(.microphone, 1, 3, "Sounds good"),
              volatile(.microphone, 4, 5, "and then", finalizedThrough: 3.5))
        XCTAssertEqual(rows, [speech(.me, 1, "Sounds good"), speech(.me, 4, "and then", isFinal: false)])

        apply(volatile(.microphone, 4, 6, "and then we ship", finalizedThrough: 3.5))
        XCTAssertEqual(rows, [speech(.me, 1, "Sounds good"), speech(.me, 4, "and then we ship", isFinal: false)])
    }

    func testALateFinalReplacesTheVolatileTextThatAFinalizationTimeAlreadyKept() {
        apply(volatile(.microphone, 1, 3, "Sounds good"),
              volatile(.microphone, 4, 5, "and then", finalizedThrough: 3.5),
              final(.microphone, 1, 3, "Sounds good."))

        XCTAssertEqual(rows, [speech(.me, 1, "Sounds good."), speech(.me, 4, "and then", isFinal: false)])
    }

    func testAMicrophoneFinalThatEchoesASystemFinalIsNotShown() {
        apply(final(.system, 10, 14, "We should move the launch to Friday"),
              final(.microphone, 10.5, 14.2, "we should move the launch to friday"))

        XCTAssertEqual(rows, [speech(.them, 10, "We should move the launch to Friday")])
    }

    func testASystemFinalThatArrivesLaterRemovesTheEarlierMicrophoneEcho() {
        apply(final(.microphone, 10.5, 14.2, "we should move the launch to friday"))
        XCTAssertEqual(rows, [speech(.me, 10.5, "we should move the launch to friday")])

        apply(final(.system, 10, 14, "We should move the launch to Friday"))
        XCTAssertEqual(rows, [speech(.them, 10, "We should move the launch to Friday")])
    }

    func testAVolatileMicrophoneEchoShowsUntilItIsFinal() {
        apply(final(.system, 10, 14, "We should move the launch to Friday"),
              volatile(.microphone, 10.5, 13, "we should move the launch"))
        XCTAssertTrue(rows.contains(speech(.me, 10.5, "we should move the launch", isFinal: false)))

        apply(final(.microphone, 10.5, 14.2, "we should move the launch to friday"))
        XCTAssertEqual(rows, [speech(.them, 10, "We should move the launch to Friday")])
    }

    func testFinalRowsComeInStartOrderWithThemFirstOnATie() {
        apply(final(.microphone, 4, 5, "Sounds good."),
              final(.microphone, 8, 9, "Right on time."),
              final(.system, 1, 3, "Hello everyone."),
              final(.system, 8, 10, "Starting now, team."))

        XCTAssertEqual(rows, [speech(.them, 1, "Hello everyone."), speech(.me, 4, "Sounds good."),
                              speech(.them, 8, "Starting now, team."), speech(.me, 8, "Right on time.")])
    }

    /// Several people in one room share the microphone track, so a short gap can be a new speaker.
    func testFinalsOfOneTrackHalfASecondApartShowAsTwoRows() {
        apply(final(.microphone, 1, 3, "I think we should wait."), final(.microphone, 3.5, 5, "No, let's ship it."))

        XCTAssertEqual(rows, [speech(.me, 1, "I think we should wait."), speech(.me, 3.5, "No, let's ship it.")])
    }

    func testEachPhraseOfAFinalResultIsARowAtTheTimeItStarted() {
        apply(.result(LiveResult(track: .microphone, start: 1, end: 6,
                                 phrases: [phrase(1.2, 3, "I think we should wait."), phrase(3.4, 5.8, "No, let's ship it.")],
                                 isFinal: true, finalizedThrough: 6)))

        XCTAssertEqual(rows, [speech(.me, 1.2, "I think we should wait."), speech(.me, 3.4, "No, let's ship it.")])
    }

    func testAVolatileResultShowsARowPerPhraseAndTheNextOneReplacesThemAll() {
        apply(.result(LiveResult(track: .microphone, start: 1, end: 5,
                                 phrases: [phrase(1, 2.5, "I think we wait."), phrase(3, 4.8, "No, we")],
                                 isFinal: false, finalizedThrough: 0)))
        XCTAssertEqual(rows, [speech(.me, 1, "I think we wait.", isFinal: false), speech(.me, 3, "No, we", isFinal: false)])

        apply(volatile(.microphone, 1, 6, "I think we wait, now we ship"))
        XCTAssertEqual(rows, [speech(.me, 1, "I think we wait, now we ship", isFinal: false)])
    }

    func testAVolatileTailTakesItsPlaceByStartAmongTheFinalRows() {
        apply(volatile(.microphone, 10, 11, "Right, so"), final(.system, 12, 13, "Okay then."))

        XCTAssertEqual(rows, [speech(.me, 10, "Right, so", isFinal: false), speech(.them, 12, "Okay then.")])
    }

    func testVolatileTailsThatStartTogetherShowThemFirst() {
        apply(volatile(.microphone, 4, 5, "Right"), volatile(.system, 4, 6, "So the plan"))

        XCTAssertEqual(rows, [speech(.them, 4, "So the plan", isFinal: false), speech(.me, 4, "Right", isFinal: false)])
    }

    func testSettleTailsTurnsEachVolatileTailIntoAFinalRow() {
        apply(volatile(.system, 50, 53, "So the plan is"), volatile(.microphone, 55, 56, "Right"))

        live.settleTails()

        XCTAssertEqual(rows, [speech(.them, 50, "So the plan is"), speech(.me, 55, "Right")])
    }

    func testSettleTailsShowsEveryPhraseOfATailAsFinal() {
        apply(.result(LiveResult(track: .microphone, start: 50, end: 56,
                                 phrases: [phrase(50, 52, "That works for me."), phrase(53, 55.5, "Not for me")],
                                 isFinal: false, finalizedThrough: 0)))

        live.settleTails()

        XCTAssertEqual(rows, [speech(.me, 50, "That works for me."), speech(.me, 53, "Not for me")])
    }

    /// At Pause the analyzer can still hold audio from before the pause, so results for the
    /// settled words can come after settleTails.
    func testALaterResultReplacesASettledTailInsteadOfRepeatingIt() {
        apply(volatile(.system, 50, 53, "So the plan"))
        live.settleTails()

        apply(volatile(.system, 50, 54, "So the plan is"))
        XCTAssertEqual(rows, [speech(.them, 50, "So the plan is", isFinal: false)])

        apply(final(.system, 50, 55, "So the plan is to ship."))
        XCTAssertEqual(rows, [speech(.them, 50, "So the plan is to ship.")])
    }

    func testRowTimesAreInRecordedTimeWithoutTheResumeGap() {
        clock.pause(at: HostTime(seconds: 160))
        clock.resume(at: HostTime(seconds: 190))

        // File position 65 is 60 s recorded, the 3 s resume gap, and 2 s after the resume.
        apply(final(.system, 65, 66, "Welcome back."), volatile(.microphone, 67, 68, "Thanks"))

        let speechRows = rows.filter { if case .speech = $0.content { return true } else { return false } }
        XCTAssertEqual(speechRows, [speech(.them, 62, "Welcome back."), speech(.me, 64, "Thanks", isFinal: false)])
    }

    func testAPauseRowAppearsAtThePausesRecordedTimeWithItsDurationOnceResumed() {
        apply(final(.system, 50, 55, "See you after the break."))
        clock.pause(at: HostTime(seconds: 160))
        XCTAssertEqual(rows, [speech(.them, 50, "See you after the break."), LiveRow(at: 60, content: .pause(duration: nil))])

        clock.resume(at: HostTime(seconds: 190))
        apply(final(.system, 63, 64, "Welcome back."))
        XCTAssertEqual(rows, [speech(.them, 50, "See you after the break."), LiveRow(at: 60, content: .pause(duration: 30)),
                              speech(.them, 60, "Welcome back.")])
    }

    func testBehindIsTheAgeOfTheNewestResultWhenItArrivedFromFourSeconds() {
        apply(final(.system, 20, 24, "Six seconds old."), at: 130)
        XCTAssertEqual(live.preview(on: clock).behind, 6)

        apply(volatile(.microphone, 28, 29, "One second old"), at: 130)
        XCTAssertNil(live.preview(on: clock).behind)
    }

    func testStatusIsPreparingUntilStartedThenLive() {
        XCTAssertEqual(live.preview(on: clock).status, .preparing)

        apply(.started)
        XCTAssertEqual(live.preview(on: clock).status, .live)
    }

    func testAFirstResultMakesTheStatusLive() {
        apply(volatile(.system, 1, 2, "Hello"))

        XCTAssertEqual(live.preview(on: clock).status, .live)
    }

    func testUnavailableKeepsItsMessage() {
        let reason = "Live transcript is not available for Finnish on this Mac."
        apply(.unavailable(reason), .started, volatile(.system, 1, 2, "Hello"), .failed("The engine stopped."))

        XCTAssertEqual(live.preview(on: clock), LivePreview(status: .unavailable(reason), rows: [], behind: nil))
    }

    func testFailedKeepsTheRowsAndIgnoresLaterResults() {
        apply(.started, final(.system, 1, 2, "Hello."), .failed("The engine stopped."),
              final(.system, 3, 4, "Later."), .started)

        XCTAssertEqual(live.preview(on: clock).status, .failed("The engine stopped."))
        XCTAssertEqual(rows, [speech(.them, 1, "Hello.")])
    }

    func testTextIsTrimmedAndEmptyOrWhitespaceTextAddsNoRow() {
        apply(volatile(.system, 1, 2, " Hello there "))
        XCTAssertEqual(rows, [speech(.them, 1, "Hello there", isFinal: false)])

        apply(volatile(.system, 1, 2, "  "), final(.microphone, 3, 4, ""), volatile(.microphone, 5, 6, " \n"))
        XCTAssertEqual(rows, [])
    }
}
