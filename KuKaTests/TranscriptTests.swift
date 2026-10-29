import XCTest
@testable import KuKa

final class TranscriptTests: XCTestCase {
    private func segment(_ start: TimeInterval, _ end: TimeInterval, _ text: String) -> TranscriptSegment {
        TranscriptSegment(start: start, end: end, text: text)
    }

    private func merge(me: [TranscriptSegment] = [], them: [TranscriptSegment] = [],
                       rooms: RoomLabels = .notDiarized) -> [TranscriptLine] {
        Transcript.merge([.microphone: me, .system: them], rooms: rooms)
    }

    private func voices(_ turns: (voice: Int, start: TimeInterval, end: TimeInterval)...) -> RoomLabels {
        .voices(RoomVoices(turns.map { VoiceTurn(voice: $0.voice, start: $0.start, end: $0.end) })!)
    }

    func testMergeInterleavesTheTracksByStartTime() {
        let lines = merge(me: [segment(4, 5, "Sounds good")],
                          them: [segment(1, 3, "Let's ship on Friday"), segment(8, 9, "Great, thanks")])

        XCTAssertEqual(lines, [
            TranscriptLine(speaker: .them, start: 1, text: "Let's ship on Friday"),
            TranscriptLine(speaker: .me, start: 4, text: "Sounds good"),
            TranscriptLine(speaker: .them, start: 8, text: "Great, thanks"),
        ])
    }

    func testMergeJoinsASpeakersSegmentsWhileTheGapIsShort() {
        let lines = merge(them: [segment(1, 3, "Hello"), segment(4, 6, "everyone."), segment(9, 10, "Next topic.")])

        XCTAssertEqual(lines, [
            TranscriptLine(speaker: .them, start: 1, text: "Hello everyone."),
            TranscriptLine(speaker: .them, start: 9, text: "Next topic."),
        ])
    }

    func testMergeDoesNotJoinAcrossTheOtherSpeaker() {
        let lines = merge(me: [segment(3.2, 3.6, "Yes")], them: [segment(1, 3, "Ready?"), segment(4, 5, "Good.")])

        XCTAssertEqual(lines.map(\.text), ["Ready?", "Yes", "Good."])
    }

    func testMergePutsThemFirstWhenBothStartTogether() {
        let lines = merge(me: [segment(2, 3, "Right on time")], them: [segment(2, 4, "Starting now team")])

        XCTAssertEqual(lines.map(\.speaker), [.them, .me])
    }

    func testMergeDropsMicrophoneEchoesOfTheSystemTrack() {
        let lines = merge(me: [segment(10.5, 14.2, "We should move the launch to Friday."), segment(20, 21, "Agreed.")],
                          them: [segment(10, 14, "we should move the launch to friday")])

        XCTAssertEqual(lines, [
            TranscriptLine(speaker: .them, start: 10, text: "we should move the launch to friday"),
            TranscriptLine(speaker: .me, start: 20, text: "Agreed."),
        ])
    }

    func testMergeDropsAMeasuredSpeakerEchoSplitInTwo() {
        let them = segment(4.98, 10.56, "The quick brown fox jumps over the lazy dog, released 2.4 ships on Tuesday.")
        let lines = merge(me: [segment(6.0, 8.64, "The quick brown fox jumps over the lazy dog."),
                               segment(8.64, 11.64, "Release 2.4 ships on Tuesday.")],
                          them: [them])

        XCTAssertEqual(lines, [TranscriptLine(speaker: .them, start: 4.98, text: them.text)])
    }

    func testMergeSkipsSegmentsWithoutText() {
        XCTAssertEqual(merge(me: [segment(1, 2, "  ")], them: [segment(3, 4, "Hi")]).map(\.text), ["Hi"])
    }

    func testRoomVoicesAreNumberedInTheOrderOfTheirFirstLine() {
        let lines = merge(me: [segment(1, 2, "Let's start with the budget."), segment(4, 5, "I have a question about it."),
                               segment(8, 9, "Go ahead.")],
                          rooms: voices((7, 0.5, 2.5), (3, 3.5, 5.5), (7, 7.5, 9.5)))

        XCTAssertEqual(lines, [
            TranscriptLine(speaker: .room(1), start: 1, text: "Let's start with the budget."),
            TranscriptLine(speaker: .room(2), start: 4, text: "I have a question about it."),
            TranscriptLine(speaker: .room(1), start: 8, text: "Go ahead."),
        ])
    }

    func testTheJoinJoinsOnlyLinesWithTheSameRoomLabel() {
        let rooms = voices((1, 0.5, 2.2), (2, 2.3, 3.2), (1, 3.3, 4.5), (2, 9.5, 11.5))
        let apart = merge(me: [segment(1, 2, "Ready to start the review?"), segment(2.5, 3, "Yes."), segment(3.5, 4, "Good."),
                               segment(10, 11, "Next item is the budget.")], rooms: rooms)
        let together = merge(me: [segment(1, 2, "Ready to start the review?"), segment(3.5, 4, "Good."),
                                  segment(10, 11, "Next item is the budget.")], rooms: rooms)

        XCTAssertEqual(apart.map(\.speaker), [.room(1), .room(2), .room(1), .room(2)])
        XCTAssertEqual(together, [
            TranscriptLine(speaker: .room(1), start: 1, text: "Ready to start the review? Good."),
            TranscriptLine(speaker: .room(2), start: 10, text: "Next item is the budget."),
        ])
    }

    func testAnEchoOfThemIsDroppedWhateverItsVoiceAndTakesNoNumber() {
        let lines = merge(me: [segment(10.5, 14.2, "We should move the launch to Friday."),
                               segment(20, 21, "Agreed, Friday works for us."), segment(24, 25, "Me too, Friday is fine.")],
                          them: [segment(10, 14, "we should move the launch to friday")],
                          rooms: voices((9, 10, 15), (4, 19, 22), (5, 23, 26)))

        XCTAssertEqual(lines, [
            TranscriptLine(speaker: .them, start: 10, text: "we should move the launch to friday"),
            TranscriptLine(speaker: .room(1), start: 20, text: "Agreed, Friday works for us."),
            TranscriptLine(speaker: .room(2), start: 24, text: "Me too, Friday is fine."),
        ])
    }

    func testOneVoiceOnTheMicrophoneStaysMe() {
        let lines = merge(me: [segment(1, 2, "Let's start."), segment(8, 9, "Next topic.")],
                          rooms: voices((7, 0, 3), (7, 7, 10)))

        XCTAssertEqual(lines.map(\.speaker), [.me, .me])
    }

    func testAVoiceThatOnlyEchoesThemLeavesOneVoiceThatStaysMe() {
        let lines = merge(me: [segment(10.5, 14.2, "We should move the launch to Friday."), segment(20, 21, "Agreed.")],
                          them: [segment(10, 14, "we should move the launch to friday")],
                          rooms: voices((9, 10, 15), (4, 19, 22)))

        XCTAssertEqual(lines.map(\.speaker), [.them, .me])
    }

    /// The echoes are too short for the echo rule, but their voice speaks only while Them speaks.
    func testAVoiceOfShortEchoesIsDroppedAndASoloUserStaysMe() {
        let lines = merge(me: [segment(1, 2, "Okay today"), segment(5, 8, "Yes, I can hear you fine."),
                               segment(11, 12.5, "Release plan"), segment(15, 18, "The release plan looks good to me."),
                               segment(21, 22, "Wrap up")],
                          them: [segment(0, 4, "Can everyone hear me okay today"), segment(10, 14, "Let's look at the release plan"),
                                 segment(20, 24, "Any questions before we wrap up")],
                          rooms: voices((2, 0.5, 2.5), (1, 4.5, 8.5), (2, 10.5, 13), (1, 14.5, 18.5), (2, 20.5, 22.5)))

        XCTAssertEqual(lines, [
            TranscriptLine(speaker: .them, start: 0, text: "Can everyone hear me okay today"),
            TranscriptLine(speaker: .me, start: 5, text: "Yes, I can hear you fine."),
            TranscriptLine(speaker: .them, start: 10, text: "Let's look at the release plan"),
            TranscriptLine(speaker: .me, start: 15, text: "The release plan looks good to me."),
            TranscriptLine(speaker: .them, start: 20, text: "Any questions before we wrap up"),
        ])
    }

    /// Half of the voice's words are in the Them speech that its segments overlap, which is enough.
    func testAVoiceOfShortRepliesThatRepeatThemIsDropped() {
        let lines = merge(me: [segment(1, 2, "Yes, Friday"), segment(5, 8, "I think Friday works for the team."),
                               segment(11, 12, "Budget, sure"), segment(15, 18, "I can review it after lunch.")],
                          them: [segment(0, 4, "Should we ship the release on Friday"),
                                 segment(10, 14, "Who can review the budget tomorrow")],
                          rooms: voices((2, 0.5, 2.5), (1, 4.5, 8.5), (2, 10.5, 12.5), (1, 14.5, 18.5)))

        XCTAssertEqual(lines, [
            TranscriptLine(speaker: .them, start: 0, text: "Should we ship the release on Friday"),
            TranscriptLine(speaker: .me, start: 5, text: "I think Friday works for the team."),
            TranscriptLine(speaker: .them, start: 10, text: "Who can review the budget tomorrow"),
            TranscriptLine(speaker: .me, start: 15, text: "I can review it after lunch."),
        ])
    }

    /// A person in the room who often talks while Them speaks: 80% of the voice's time overlaps
    /// Them, but an echo would also repeat Them's words.
    func testAVoiceThatTalksOverThemWithItsOwnWordsKeepsItsLinesAndGetsARoomLabel() {
        let lines = merge(me: [segment(2, 4, "I printed copies for everyone here"),
                               segment(20, 23, "Can someone close the door please"),
                               segment(24, 27, "Thanks, that makes sense to me.")],
                          them: [segment(0, 10, "Let's walk through the quarterly budget numbers one line at a time"),
                                 segment(12, 22, "The travel costs went up because of the conference in Berlin")],
                          rooms: voices((2, 1.5, 4.5), (2, 19.5, 23.2), (1, 23.5, 27.5)))

        XCTAssertEqual(lines.map(\.speaker), [.them, .room(1), .them, .room(1), .room(2)])
    }

    func testASecondPersonWithSixWordsAwayFromThemGetsARoomLabel() {
        let lines = merge(me: [segment(4, 7, "The numbers look good this quarter."), segment(8, 10, "I agree, they look fine.")],
                          them: [segment(0, 3, "Let's start with the numbers")],
                          rooms: voices((1, 3.5, 7.5), (2, 7.5, 10.5)))

        XCTAssertEqual(lines.map(\.speaker), [.them, .room(1), .room(2)])
    }

    func testAVoiceWithTooFewWordsTakesTheLabelOfTheNearestCountedVoice() {
        let lines = merge(me: [segment(0, 3, "Let's go over the budget first."), segment(5.5, 6, "Right."),
                               segment(11, 11.5, "Sure."), segment(15, 18, "I have the budget numbers ready.")],
                          rooms: voices((1, 0, 3.2), (3, 5.4, 6.2), (3, 10.9, 11.7), (2, 14.8, 18.2)))

        XCTAssertEqual(lines, [
            TranscriptLine(speaker: .room(1), start: 0, text: "Let's go over the budget first."),
            TranscriptLine(speaker: .room(1), start: 5.5, text: "Right."),
            TranscriptLine(speaker: .room(2), start: 11, text: "Sure."),
            TranscriptLine(speaker: .room(2), start: 15, text: "I have the budget numbers ready."),
        ])
    }

    func testWithoutRoomVoicesTheMicrophoneStaysMe() {
        for rooms in [RoomLabels.notDiarized, .failed(.noVoices)] {
            XCTAssertEqual(merge(me: [segment(1, 2, "Hello.")], rooms: rooms).map(\.speaker), [.me], "\(rooms)")
        }
    }

    func testTheCallIsNeverARoomLabel() {
        let lines = merge(me: [segment(1, 2, "Are we ready to begin now?"), segment(8, 9, "Yes, we can begin right away.")],
                          them: [segment(4, 5, "Let's go.")],
                          rooms: voices((1, 0, 6), (2, 7, 10)))

        XCTAssertEqual(lines.map(\.speaker), [.room(1), .them, .room(2)])
    }

    func testSpeakerLabelsAndTracks() {
        XCTAssertEqual(Speaker.me.label, "Me")
        XCTAssertEqual(Speaker.them.label, "Them")
        XCTAssertEqual(Speaker.room(3).label, "Room 3")
        XCTAssertEqual(Speaker.room(1).track, .microphone)
        XCTAssertEqual(Speaker.me.track, .microphone)
        XCTAssertEqual(Speaker.them.track, .system)
    }

    func testEchoNeedsSixtyPercentOfTheMicrophoneWords() {
        let system = segment(10, 14, "We should move the launch to Friday")

        XCTAssertTrue(Transcript.isEcho(segment(11, 13, "we should move it later"), of: system))
        XCTAssertFalse(Transcript.isEcho(segment(11, 13, "we should go somewhere else"), of: system))
    }

    func testEchoNeedsTheSegmentsToOverlapWithinOneSecond() {
        let system = segment(10, 14, "We should move the launch to Friday")

        XCTAssertTrue(Transcript.isEcho(segment(14.8, 16, "move the launch"), of: system))
        XCTAssertFalse(Transcript.isEcho(segment(15.5, 16, "move the launch"), of: system))
    }

    func testShortMicrophoneRepliesAreNeverEchoes() {
        XCTAssertFalse(Transcript.isEcho(segment(11, 12, "to Friday"), of: segment(10, 14, "move the launch to Friday")))
        XCTAssertTrue(Transcript.isEcho(segment(11, 12, "launch to Friday"), of: segment(10, 14, "move the launch to Friday")))
    }

    func testMarkdownListsOneTimestampedParagraphPerLine() {
        let markdown = Transcript.markdown([
            TranscriptLine(speaker: .them, start: 1.7, text: "Let's ship on Friday"),
            TranscriptLine(speaker: .me, start: 3604, text: "Sounds good"),
        ], title: "Meeting on 2026-10-23 at 14:02", duration: 3729, by: "Whisper large-v3-v20240930_turbo", after: [],
           rooms: .notDiarized)

        XCTAssertEqual(markdown, """
        # Meeting on 2026-10-23 at 14:02

        Duration: 01:02:09

        Transcript by Whisper large-v3-v20240930_turbo.

        "Me" is the microphone of the Mac that recorded the meeting. It hears the person who recorded the meeting and anyone in the same room. "Them" is everyone else on the call.

        **[00:00:01] Them:** Let's ship on Friday

        **[01:00:04] Me:** Sounds good

        """)
    }

    private let legends: [(name: String, text: String)] = [
        ("rooms", "\"Room 1\", \"Room 2\", and so on are voices on the microphone of the Mac that recorded the meeting. The microphone hears the person who recorded the meeting and anyone in the same room. Ku-Ka told the voices apart on this Mac and numbered them in the order they first spoke. Two people with similar voices can share one label, and one person can get two labels. No label tells which voice is the person who recorded the meeting. \"Them\" is everyone else on the call."),
        ("current", "\"Me\" is the microphone of the Mac that recorded the meeting. It hears the person who recorded the meeting and anyone in the same room. \"Them\" is everyone else on the call."),
        ("older", "\"Me\" is the person who recorded the meeting. \"Them\" is everyone else on the call."),
    ]

    func testSummaryContentStartsAfterTheCurrentOrTheOlderSpeakerLegend() {
        for (name, legend) in legends {
            let markdown = """
            # Meeting on 2026-10-23 at 14:02

            Duration: 00:01:00

            Transcript by Whisper large-v3-v20240930_turbo.

            \(legend)

            **[00:00:01] Them:** Let's ship on Friday

            """

            XCTAssertEqual(Transcript.contentForSummary(markdown), "**[00:00:01] Them:** Let's ship on Friday\n", name)
        }
    }

    func testMarkdownListsWhatFailedBeforeTheTranscriberThatWroteIt() {
        let markdown = Transcript.markdown(
            [TranscriptLine(speaker: .them, start: 1, text: "Let's ship on Friday")],
            title: "Meeting on 2026-10-23 at 14:02", duration: 60, by: "Apple speech recognition",
            after: [TranscriberFailure(transcriber: "Whisper large-v3-v20240930_turbo", stage: .download,
                                       message: "The Internet connection appears to be offline.")],
            rooms: .notDiarized)

        XCTAssertEqual(markdown, """
        # Meeting on 2026-10-23 at 14:02

        Duration: 00:01:00

        Transcript by Apple speech recognition. Tried first:

        - Whisper large-v3-v20240930_turbo could not download its model: The Internet connection appears to be offline.

        "Me" is the microphone of the Mac that recorded the meeting. It hears the person who recorded the meeting and anyone in the same room. "Them" is everyone else on the call.

        **[00:00:01] Them:** Let's ship on Friday

        """)
    }

    private let whisper = "Whisper large-v3-v20240930_turbo"
    private let offline = TranscriberFailure(transcriber: "Whisper large-v3-v20240930_turbo", stage: .download,
                                             message: "The Internet connection appears to be offline.")
    private let shipOnFriday = TranscriptLine(speaker: .them, start: 1, text: "Let's ship on Friday")

    func testMarkdownWithRoomVoicesExplainsRoomLabels() {
        let markdown = Transcript.markdown([
            shipOnFriday,
            TranscriptLine(speaker: .room(1), start: 4, text: "Sounds good"),
            TranscriptLine(speaker: .room(2), start: 6, text: "Friday works for me"),
        ], title: "Meeting on 2026-10-23 at 14:02", duration: 60, by: whisper, after: [],
           rooms: voices((7, 3.5, 5.5), (3, 5.5, 8)))

        XCTAssertEqual(markdown, """
        # Meeting on 2026-10-23 at 14:02

        Duration: 00:01:00

        Transcript by Whisper large-v3-v20240930_turbo.

        "Room 1", "Room 2", and so on are voices on the microphone of the Mac that recorded the meeting. The microphone hears the person who recorded the meeting and anyone in the same room. Ku-Ka told the voices apart on this Mac and numbered them in the order they first spoke. Two people with similar voices can share one label, and one person can get two labels. No label tells which voice is the person who recorded the meeting. "Them" is everyone else on the call.

        **[00:00:01] Them:** Let's ship on Friday

        **[00:00:04] Room 1:** Sounds good

        **[00:00:06] Room 2:** Friday works for me

        """)
    }

    func testMarkdownWithOneRoomVoiceIsTheTranscriptWithoutRoomLabels() {
        let lines = merge(me: [segment(4, 5, "Sounds good")], them: [segment(1, 3, "Let's ship on Friday")],
                          rooms: voices((7, 3.5, 5.5)))
        func markdown(_ rooms: RoomLabels) -> String {
            Transcript.markdown(lines, title: "Meeting on 2026-10-23 at 14:02", duration: 60, by: whisper, after: [],
                                rooms: rooms)
        }

        XCTAssertEqual(markdown(voices((7, 3.5, 5.5))), markdown(.notDiarized))
    }

    func testMarkdownWithoutRoomLabelsSaysWhyUnderTheByline() {
        let markdown = Transcript.markdown([shipOnFriday, TranscriptLine(speaker: .me, start: 4, text: "Sounds good")],
                                           title: "Meeting on 2026-10-23 at 14:02", duration: 60, by: whisper, after: [],
                                           rooms: .failed(.download("The Internet connection appears to be offline.")))

        XCTAssertEqual(markdown, """
        # Meeting on 2026-10-23 at 14:02

        Duration: 00:01:00

        Transcript by Whisper large-v3-v20240930_turbo.

        There are no room labels. SpeakerKit could not download its model: The Internet connection appears to be offline.

        "Me" is the microphone of the Mac that recorded the meeting. It hears the person who recorded the meeting and anyone in the same room. "Them" is everyone else on the call.

        **[00:00:01] Them:** Let's ship on Friday

        **[00:00:04] Me:** Sounds good

        """)
    }

    func testTheFailureLineComesAfterTheTranscribersTriedFirst() {
        let markdown = Transcript.markdown([shipOnFriday], title: "Meeting on 2026-10-23 at 14:02", duration: 60,
                                           by: "Apple speech recognition", after: [offline], rooms: .failed(.noVoices))

        XCTAssertEqual(markdown, """
        # Meeting on 2026-10-23 at 14:02

        Duration: 00:01:00

        Transcript by Apple speech recognition. Tried first:

        - Whisper large-v3-v20240930_turbo could not download its model: The Internet connection appears to be offline.

        There are no room labels. SpeakerKit found no voices on the microphone track.

        "Me" is the microphone of the Mac that recorded the meeting. It hears the person who recorded the meeting and anyone in the same room. "Them" is everyone else on the call.

        **[00:00:01] Them:** Let's ship on Friday

        """)
    }

    func testEachRoomLabelFailureReadsAsOneSentence() {
        XCTAssertEqual(RoomLabelFailure.download("The network connection was lost.").description,
                       "SpeakerKit could not download its model: The network connection was lost.")
        XCTAssertEqual(RoomLabelFailure.load("Model is corrupt.").description,
                       "SpeakerKit could not load its model: Model is corrupt.")
        XCTAssertEqual(RoomLabelFailure.diarize("The file could not be read.").description,
                       "SpeakerKit could not tell the voices apart: The file could not be read.")
        XCTAssertEqual(RoomLabelFailure.noVoices.description, "SpeakerKit found no voices on the microphone track.")
        XCTAssertEqual(RoomLabelFailure.tooLong.description,
                       "Ku-Ka skipped them, because the microphone track is longer than 3 hours.")
        XCTAssertEqual(RoomLabelFailure.earlierAttemptStopped.description,
                       "Ku-Ka skipped them, because an earlier attempt stopped while it told the voices apart, for example in a crash.")
    }

    func testSummaryContentStartsAfterEveryLegendThatMarkdownWrites() {
        let me = [segment(4, 5, "Sounds good, I can ship it"), segment(6, 7, "Friday works for me too")]
        let them = [segment(1, 3, "Let's ship on Friday")]
        let together = "**[00:00:01] Them:** Let's ship on Friday\n\n**[00:00:04] Me:** Sounds good, I can ship it Friday works for me too\n"
        let cases: [(rooms: RoomLabels, content: String)] = [
            (.notDiarized, together),
            (voices((7, 3.5, 5.5), (3, 5.5, 8)),
             "**[00:00:01] Them:** Let's ship on Friday\n\n**[00:00:04] Room 1:** Sounds good, I can ship it\n\n**[00:00:06] Room 2:** Friday works for me too\n"),
            (.failed(.load("x")), together),
        ]
        for (rooms, content) in cases {
            for failures in [[], [offline]] {
                let markdown = Transcript.markdown(merge(me: me, them: them, rooms: rooms), title: "Meeting on 2026-10-23 at 14:02",
                                                   duration: 60, by: whisper, after: failures, rooms: rooms)

                XCTAssertEqual(Transcript.contentForSummary(markdown), content, "\(rooms), \(failures.count) failures")
            }
        }
    }

    private func corrector(_ list: String) -> Corrector {
        KnownWordsList(markdown: list).corrector
    }

    private func heardTranscript(_ lines: [TranscriptLine]) -> String {
        Transcript.markdown(lines, title: "Meeting on 2026-10-23 at 14:02", duration: 60, by: whisper, after: [],
                            rooms: .notDiarized)
    }

    /// The forms on the list's last line occur only in the title, the byline, the legend, and the labels.
    func testKnownWordsChangeOnlyTheSpokenTextAndEndWithOneNote() {
        let heard = heardTranscript([
            TranscriptLine(speaker: .them, start: 1, text: "Convio and Yuri joined. Convio's plan is ready."),
            TranscriptLine(speaker: .me, start: 4, text: "I will send it to convio."),
        ])

        let corrected = Transcript.corrected(heard, by: corrector("""
        - Convio → **Konvio** ✓
        - Yuri → **Jyri** ✓
        - Whisper / meeting / them / me → **Quorix** ✓
        """))

        XCTAssertEqual(corrected.markdown, """
        # Meeting on 2026-10-23 at 14:02

        Duration: 00:01:00

        Transcript by Whisper large-v3-v20240930_turbo.

        "Me" is the microphone of the Mac that recorded the meeting. It hears the person who recorded the meeting and anyone in the same room. "Them" is everyone else on the call.

        **[00:00:01] Them:** Konvio and Jyri joined. Konvio's plan is ready.

        **[00:00:04] Me:** I will send it to Konvio.

        ---

        Known words applied: Convio → Konvio (3), Yuri → Jyri (1).

        """)
        XCTAssertEqual(corrected.applied, [AppliedCorrection(heard: "Convio", right: "Konvio", count: 3),
                                           AppliedCorrection(heard: "Yuri", right: "Jyri", count: 1)])
    }

    func testKnownWordsChangeTheTextAfterAnyLabelButNeverTheLabel() {
        let heard = heardTranscript([
            TranscriptLine(speaker: .them, start: 1, text: "Is Convio in the room?"),
            TranscriptLine(speaker: .room(1), start: 4, text: "Convio is here."),
            TranscriptLine(speaker: .room(2), start: 6, text: "Room two agrees."),
        ])

        let corrected = Transcript.corrected(heard, by: corrector("- Convio → **Konvio** ✓\n- room → **Alpha Bay** ✓\n"))

        XCTAssertEqual(corrected.markdown, heard
            .replacingOccurrences(of: "Is Convio in the room?", with: "Is Konvio in the Alpha Bay?")
            .replacingOccurrences(of: "Convio is here.", with: "Konvio is here.")
            .replacingOccurrences(of: "Room two agrees.", with: "Alpha Bay two agrees.")
            + "\n---\n\nKnown words applied: Convio → Konvio (2), room → Alpha Bay (2).\n")
    }

    func testWithoutAReplacementTheTranscriptIsTheHeardTextByteForByte() {
        let heard = heardTranscript([TranscriptLine(speaker: .them, start: 1, text: "Let's  ship\tConvio on Friday ")])

        let corrected = Transcript.corrected(heard, by: corrector("- Whisper / meeting → **Quorix** ✓\n- Convio → **Konvio**\n"))

        XCTAssertEqual(corrected, CorrectedTranscript(body: heard, applied: []))
        XCTAssertEqual(corrected.markdown, heard)
    }

    /// Without the line break, "---" would turn the last line into a heading.
    func testTheNoteAfterTextWithoutAFinalLineBreakStartsAfterAnEmptyLine() {
        let corrected = Transcript.corrected("**[00:00:07] Me:** Ask Convio.", by: corrector("- Convio → **Konvio** ✓\n"))

        XCTAssertEqual(corrected.markdown, "**[00:00:07] Me:** Ask Konvio.\n\n---\n\nKnown words applied: Convio → Konvio (1).\n")
    }

    func testWithoutCorrectionNoteRemovesOnlyTheNote() {
        let heard = heardTranscript([TranscriptLine(speaker: .them, start: 1, text: "Convio and Yuri joined.")])
        let corrected = Transcript.corrected(heard, by: corrector("- Convio → **Konvio** ✓\n"))

        XCTAssertEqual(Transcript.withoutCorrectionNote(corrected.markdown),
                       heard.replacingOccurrences(of: "Convio and", with: "Konvio and"))
        XCTAssertEqual(Transcript.withoutCorrectionNote(heard), heard)
    }

    func testTheSummaryContentOfTheCorrectedBodyHasNoKnownWordsNoteAfterEveryLegendAndWithoutOne() {
        let header = "# Meeting on 2026-10-23 at 14:02\n\nDuration: 00:01:00\n\nTranscript by Whisper large-v3-v20240930_turbo.\n\n"
        let cases = legends.map { (name: $0.name, header: header + $0.text + "\n\n") } + [("no legend", "")]
        for (name, header) in cases {
            let heard = header + "**[00:00:01] Them:** Let's ship Convio on Friday\n"
            let corrected = Transcript.corrected(heard, by: corrector("- Convio → **Konvio** ✓\n"))

            XCTAssertEqual(corrected.body, Transcript.withoutCorrectionNote(corrected.markdown), name)
            XCTAssertEqual(Transcript.contentForSummary(corrected.body), "**[00:00:01] Them:** Let's ship Konvio on Friday\n", name)
        }
    }

    func testThePlaceOfAQuoteIsTheLabelAndTimeOfTheFirstLineThatHasItComparedFolded() {
        let markdown = heardTranscript([
            TranscriptLine(speaker: .them, start: 751, text: "We should ask Convio about the rollout."),
            TranscriptLine(speaker: .room(2), start: 760, text: "Jyri has  the numbers for Konvio’s plan."),
            TranscriptLine(speaker: .them, start: 770, text: "Mäki agreed about the rollout."),
        ])

        XCTAssertEqual(Transcript.place(of: "we SHOULD ask\nconvio", in: markdown), "Them at 00:12:31")
        XCTAssertEqual(Transcript.place(of: "Jyri has the numbers for Konvio's plan.", in: markdown), "Room 2 at 00:12:40")
        XCTAssertEqual(Transcript.place(of: "the rollout", in: markdown), "Them at 00:12:31")
        XCTAssertEqual(Transcript.place(of: "Ma\u{0308}ki agreed", in: markdown), "Them at 00:12:50")
    }

    func testAQuoteThatNoTranscriptLineHasHasNoPlace() {
        let markdown = heardTranscript([TranscriptLine(speaker: .them, start: 1, text: "We should ask Convio about the rollout.")])

        XCTAssertNil(Transcript.place(of: "ship on Friday", in: markdown))
        XCTAssertNil(Transcript.place(of: "recorded the meeting", in: markdown), "the legend is not a transcript line")
        XCTAssertNil(Transcript.place(of: "Them:", in: markdown), "the label is not spoken text")
        XCTAssertNil(Transcript.place(of: " \n", in: markdown))
    }
}
