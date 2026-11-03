import AppKit
import XCTest
@testable import KuKa

final class MeetingTranscriptTextTests: XCTestCase {
    private func speech(_ text: String, at time: TimeInterval = 0, isFinal: Bool = true) -> LiveRow {
        LiveRow(at: time, content: .speech(.them, text: text, isFinal: isFinal))
    }

    /// Applies `rows` after `start` the way the drawer does, and returns the change.
    private func change(from start: [LiveRow], to rows: [LiveRow])
        -> (old: String, replacement: TranscriptText.Replacement, transcript: TranscriptText) {
        var transcript = TranscriptText()
        let old = transcript.update(to: start, shown: "").text.string
        let replacement = transcript.update(to: rows, shown: old)
        return (old, replacement, transcript)
    }

    private func applied(_ replacement: TranscriptText.Replacement, to old: String) -> String {
        let old = old as NSString
        return old.replacingCharacters(in: NSRange(location: replacement.location, length: old.length - replacement.location),
                                       with: replacement.text.string)
    }

    func testAppendingARowKeepsAllOfTheOldText() {
        let first = speech("We start tomorrow.")
        let second = speech("Mira owns the checklist.", at: 4)
        let result = change(from: [first], to: [first, second])

        XCTAssertEqual(result.replacement.location, (result.old as NSString).length)
        XCTAssertEqual(applied(result.replacement, to: result.old), TranscriptText.render([first, second]).text.string)
        XCTAssertEqual(result.transcript.rows, [first, second])
    }

    func testAGrowingDraftKeepsItsUnchangedStart() {
        let result = change(from: [speech("Hello wor", isFinal: false)], to: [speech("Hello world", isFinal: false)])

        XCTAssertEqual(result.replacement.location, NSMaxRange((result.old as NSString).range(of: "Hello wor")))
        XCTAssertEqual(applied(result.replacement, to: result.old),
                       TranscriptText.render([speech("Hello world", isFinal: false)]).text.string)
    }

    func testAChangedRowAfterAKeptRowStartsAfterTheKeptRow() {
        let kept = speech("We start tomorrow.")
        let result = change(from: [kept, speech("Draft", at: 4, isFinal: false)], to: [kept, speech("Final", at: 4)])

        XCTAssertGreaterThanOrEqual(result.replacement.location, (TranscriptText.render([kept]).text.string as NSString).length)
        XCTAssertEqual(applied(result.replacement, to: result.old),
                       TranscriptText.render([kept, speech("Final", at: 4)]).text.string)
    }

    func testAReplacementNeverStartsInsideASurrogatePair() {
        let result = change(from: [speech("Ship 😀")], to: [speech("Ship 😃")])
        let old = result.old as NSString

        XCTAssertEqual(result.replacement.location, old.length - 4, "the whole emoji and the blank line are replaced")
        XCTAssertFalse(UTF16.isLeadSurrogate(old.character(at: result.replacement.location - 1)))
        XCTAssertEqual(applied(result.replacement, to: result.old), TranscriptText.render([speech("Ship 😃")]).text.string)
    }

    func testASelectionInKeptTextStaysAndOneInReplacedTextCollapses() {
        XCTAssertEqual(TranscriptText.selection(NSRange(location: 2, length: 5), keptBefore: 7), NSRange(location: 2, length: 5))
        XCTAssertEqual(TranscriptText.selection(NSRange(location: 2, length: 6), keptBefore: 7), NSRange(location: 2, length: 0))
        XCTAssertEqual(TranscriptText.selection(NSRange(location: 9, length: 3), keptBefore: 7), NSRange(location: 7, length: 0))
    }
}
