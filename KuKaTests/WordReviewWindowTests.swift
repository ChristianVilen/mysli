import AppKit
import XCTest
@testable import KuKa

@MainActor
final class WordReviewWindowTests: XCTestCase {
    private let convio = ["heard": "Convio", "suggestion": "Konvio", "kind": "company",
                          "quote": "We should ask CONVIO's team about the rollout.", "reason": "spelled three ways",
                          "place": "Them at 00:12:31"]
    private let yuri = ["heard": "Yuri", "suggestion": "Jyri", "kind": "person", "quote": "Yuri has the numbers."]
    private let kworix = ["heard": "Kworix", "kind": "other", "quote": "Kworix moved the launch."]
    private let myKey = ["heard": "my key", "suggestion": "Maikki", "kind": "term", "quote": "Then my key will send them."]

    private var root: URL!
    private var listURL: URL!
    private var lockURL: URL!
    private var ordinary: Set<String> = []
    private var requested: [MeetingFolder] = []
    private var opened: [URL] = []
    private var policies: [NSApplication.ActivationPolicy] = []
    private var activations = 0
    private var controller: WordReviewController!
    private var sut: WordReviewWindowController!

    override func setUp() async throws {
        let base = try makeTemporaryDirectory()
        root = base.appendingPathComponent("Meetings", isDirectory: true)
        listURL = base.appendingPathComponent("known-words.md")
        lockURL = base.appendingPathComponent("Support/known-words.lock")
        controller = WordReviewController(
            root: { [unowned self] in root },
            knownWords: KnownWordsFile(url: { [unowned self] in listURL }, lockURL: lockURL,
                                       now: { localDate(2026, 10, 28, 10, 0) }),
            isOrdinary: { [unowned self] in ordinary.contains($0) },
            requestUpdate: { [unowned self] in requested.append($0) },
            openURL: { [unowned self] in opened.append($0) })
        sut = WordReviewWindowController(controller: controller,
                                         activation: .fake(setPolicy: { [unowned self] in policies.append($0) },
                                                           activateApp: { [unowned self] in activations += 1 }))
        sut.bindController()
    }

    override func tearDown() async throws {
        sut.close()
    }

    @discardableResult
    private func reviewedMeeting(on day: Int, asking questions: [[String: String]],
                                 skipped: [String] = []) throws -> MeetingFolder {
        let meeting = try MeetingFolder.create(in: root, startingAt: localDate(2026, 10, day, 9, 0))
        try meeting.write("**[00:12:31] Them:** We should ask CONVIO's team about the rollout.\n", to: .transcript)
        try meeting.write("# \(meeting.title)\n\nAsk Convio.\n", to: .summary)
        let json = try JSONSerialization.data(withJSONObject: ["questions": questions])
        try meeting.write(String(decoding: json, as: UTF8.self), to: .questions)
        for question in try XCTUnwrap(meeting.wordReview(knownWords: .empty)).questions where skipped.contains(question.heard) {
            try meeting.saveSkip(question)
        }
        return meeting
    }

    private func views(in view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + views(in: $0) }
    }

    private var shownViews: [NSView] {
        guard sut.window?.isVisible == true, let content = sut.window?.contentView else { return [] }
        return views(in: content).filter { !$0.isHiddenOrHasHiddenAncestor }
    }

    private var texts: [String] {
        shownViews.compactMap { $0 as? NSTextField }.filter { !$0.isEditable }.map(\.stringValue)
    }

    private var field: NSTextField? {
        shownViews.compactMap { $0 as? NSTextField }.first { $0.isEditable }
    }

    private var buttonTitles: [String] {
        shownViews.compactMap { ($0 as? NSButton)?.title }
    }

    private func button(_ title: String) -> NSButton? {
        shownViews.compactMap { $0 as? NSButton }.first { $0.title == title }
    }

    private func click(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let button = button(title), button.isEnabled else {
            return XCTFail("no enabled \(title) button", file: file, line: line)
        }
        button.performClick(nil)
    }

    /// Text typed into the field, as the field's delegate hears of it.
    private func type(_ text: String) {
        guard let field else { return XCTFail("no field") }
        field.stringValue = text
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    /// A key command in the field, as the field editor sends it.
    @discardableResult
    private func command(_ selector: Selector) -> Bool {
        guard let field else {
            XCTFail("no field")
            return false
        }
        return field.delegate?.control?(field, textView: NSTextView(), doCommandBy: selector) ?? false
    }

    private var list: String? {
        try? String(contentsOf: listURL, encoding: .utf8)
    }

    func testAQuestionShowsTheMeetingThePositionThePlaceAndTheQuoteWithTheHeardFormInBold() throws {
        try reviewedMeeting(on: 23, asking: [yuri, convio, kworix], skipped: ["Yuri"])

        sut.show(nil)

        XCTAssertEqual(sut.window?.title, "Check Words")
        XCTAssertEqual(texts, ["Meeting on 2026-10-23 at 09:00", "Word 2 of 3", "Them at 00:12:31",
                               "“We should ask CONVIO's team about the rollout.”", "Why Ku-Ka asks: spelled three ways",
                               "Right word:"])
        let quote = try XCTUnwrap(shownViews.compactMap { $0 as? NSTextField }.first { $0.stringValue.hasPrefix("“") })
        let text = quote.attributedStringValue
        let bold = (0..<text.length).filter { index in
            (text.attribute(.font, at: index, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true
        }
        XCTAssertEqual(text.attributedSubstring(from: NSRange(location: bold.first ?? 0, length: bold.count)).string, "CONVIO")
        XCTAssertEqual(bold.count, "CONVIO".count, "only the heard form is bold")
    }

    func testAQuestionWithoutPlaceOrReasonLeavesThemOut() throws {
        try reviewedMeeting(on: 23, asking: [kworix])

        sut.show(nil)

        XCTAssertEqual(texts, ["Meeting on 2026-10-23 at 09:00", "Word 1 of 1", "“Kworix moved the launch.”", "Right word:"])
        XCTAssertEqual(field?.stringValue, "")
    }

    func testTheFieldStartsWithTheSuggestionAndSaveSendsItsText() throws {
        try reviewedMeeting(on: 23, asking: [convio, yuri])
        sut.show(nil)
        XCTAssertEqual(field?.stringValue, "Konvio")
        XCTAssertEqual(button("Save")?.keyEquivalent, "\r", "Save is the default button")
        XCTAssertEqual(button("Save")?.isEnabled, true)

        type("Konvia ")
        click("Save")

        XCTAssertEqual(list?.hasSuffix("- Convio → **Konvia** ✓ confirmed 2026-10-28 by Ku-Ka\n"), true, list ?? "no list")
        XCTAssertEqual(field?.stringValue, "Jyri", "the next question starts with its own suggestion")
    }

    func testSaveNeedsTextInTheField() throws {
        try reviewedMeeting(on: 23, asking: [kworix])
        sut.show(nil)
        XCTAssertEqual(button("Save")?.isEnabled, false)

        type("Quorix")
        XCTAssertEqual(button("Save")?.isEnabled, true)
        type("  ")
        XCTAssertEqual(button("Save")?.isEnabled, false)
    }

    func testReturnInTheFieldSavesAndEscClosesTheWindow() throws {
        try reviewedMeeting(on: 23, asking: [convio, yuri])
        sut.show(nil)
        let saved = "- Convio → **Konvio** ✓ confirmed 2026-10-28 by Ku-Ka\n"

        XCTAssertTrue(command(#selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(list?.hasSuffix(saved), true, list ?? "no list")

        XCTAssertTrue(command(#selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(sut.window?.isVisible, false)
        XCTAssertNil(controller.screen)
        XCTAssertEqual(list?.hasSuffix(saved), true, "saved answers stay")
    }

    func testReturnWithAnEmptyFieldSavesNothing() throws {
        let meeting = try reviewedMeeting(on: 23, asking: [kworix])
        sut.show(nil)

        command(#selector(NSResponder.insertNewline(_:)))

        XCTAssertFalse(FileManager.default.fileExists(atPath: meeting.url(for: .skipped).path))
        XCTAssertNil(list)
    }

    func testSkipAndCorrectAsHeardReachTheController() throws {
        let meeting = try reviewedMeeting(on: 23, asking: [convio, yuri])
        sut.show(nil)

        click("Skip")
        XCTAssertEqual(meeting.wordReview(knownWords: .empty)?.skipped, ["convio"])
        click("It Is Correct as Heard")

        XCTAssertEqual(meeting.wordReview(knownWords: .empty)?.skipped, ["convio"])
        XCTAssertEqual(list?.hasSuffix("- **Yuri** (correct as heard; added by Ku-Ka 2026-10-28)\n"), true, list ?? "no list")
    }

    func testTheOrdinaryWordsNoteShowsOnlyForAnOrdinaryHeardForm() throws {
        ordinary = ["my key", "yuri"]
        try reviewedMeeting(on: 23, asking: [myKey, yuri])
        let note = "“my key” is also ordinary words. Ku-Ka will not replace it in every transcript. The summary tool will check it by context."

        sut.show(nil)
        XCTAssertTrue(texts.contains(note), "\(texts)")

        click("Skip")
        XCTAssertEqual(field?.stringValue, "Jyri")
        XCTAssertFalse(texts.contains { $0.contains("ordinary words") }, "a name is never ordinary words")
    }

    func testAnErrorShowsItsTextKeepsWhatWasTypedAndGoesAtTheNextAction() throws {
        try reviewedMeeting(on: 23, asking: [convio, yuri])
        sut.show(nil)
        try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let otherKuKa = try FileLock.acquire(at: lockURL)

        type("Konvia")
        click("Save")

        XCTAssertEqual(texts.last, "Another Ku-Ka is saving to the known-words list. Try again.")
        XCTAssertEqual(field?.stringValue, "Konvia")
        otherKuKa.release()

        click("Skip")
        XCTAssertFalse(texts.contains { $0.hasPrefix("Another Ku-Ka") })
    }

    func testTheButtonsAndTheFieldHaveVoiceOverLabels() throws {
        try reviewedMeeting(on: 23, asking: [convio])
        sut.show(nil)

        XCTAssertEqual(field?.accessibilityLabel(), "Right word for “Convio”")
        XCTAssertEqual(shownViews.compactMap { ($0 as? NSButton)?.accessibilityLabel() },
                       ["Skip", "It Is Correct as Heard", "Save"])
    }

    func testTheFinishedPageOffersUpdateNotesAndNextMeetingOnlyWhenTheScreenAllows() throws {
        let meeting = try reviewedMeeting(on: 23, asking: [convio])
        try reviewedMeeting(on: 24, asking: [yuri])
        sut.show(meeting)

        click("Save")

        XCTAssertEqual(texts, ["All words checked for Meeting on 2026-10-23 at 09:00.",
                               "Update Notes makes the transcript and the summary again with your answers. It replaces changes that you made to the transcript by hand."])
        XCTAssertEqual(buttonTitles, ["Open Summary", "Update Notes", "Next Meeting", "Close"])
        XCTAssertEqual(shownViews.compactMap { ($0 as? NSButton)?.accessibilityLabel() }, buttonTitles)
    }

    func testAFinishedPageWithOnlySkipsAndNoOtherMeetingOffersOnlyTheSummary() throws {
        let meeting = try reviewedMeeting(on: 23, asking: [convio])
        sut.show(meeting)

        click("Skip")

        XCTAssertEqual(texts, ["All words checked for Meeting on 2026-10-23 at 09:00."])
        XCTAssertEqual(buttonTitles, ["Open Summary", "Close"])
    }

    func testUpdateNotesAsksTheControllerAndThenSaysTheNotesAreBeingUpdated() throws {
        let meeting = try reviewedMeeting(on: 23, asking: [convio])
        sut.show(meeting)
        click("Save")

        click("Update Notes")

        XCTAssertEqual(requested, [meeting])
        XCTAssertEqual(texts, ["All words checked for Meeting on 2026-10-23 at 09:00.",
                               "Ku-Ka is updating the notes. You get a notification when they are ready."])
        XCTAssertEqual(buttonTitles, ["Open Summary", "Close"])
    }

    func testOpenSummaryNextMeetingAndCloseReachTheController() throws {
        let meeting = try reviewedMeeting(on: 23, asking: [convio], skipped: ["Convio"])
        try reviewedMeeting(on: 24, asking: [yuri])
        sut.show(meeting)

        click("Open Summary")
        XCTAssertEqual(opened, [meeting.url(for: .summary)])
        click("Next Meeting")
        XCTAssertEqual(texts.first, "Meeting on 2026-10-24 at 09:00")
        XCTAssertEqual(field?.stringValue, "Jyri")
        click("Skip")
        click("Close")

        XCTAssertEqual(sut.window?.isVisible, false)
        XCTAssertNil(controller.screen)
    }

    func testANilScreenClosesTheWindowAndTheAppIsRegularOnlyWhileItIsOpen() throws {
        try reviewedMeeting(on: 23, asking: [convio, yuri])

        sut.show(nil)
        XCTAssertEqual(sut.window?.isVisible, true)
        click("Skip")
        XCTAssertEqual(policies, [.regular], "a new page keeps the window as it is")

        controller.close()

        XCTAssertEqual(sut.window?.isVisible, false)
        XCTAssertEqual(policies, [.regular, .accessory])
    }

    func testClosingTheWindowClosesTheReviewOnce() throws {
        try reviewedMeeting(on: 23, asking: [convio])
        var changes = 0
        sut.show(nil)
        let render = controller.onChange
        controller.onChange = { changes += 1; render?() }

        sut.close()

        XCTAssertNil(controller.screen)
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(policies, [.regular, .accessory])
    }

    func testEscOnTheFinishedPageClosesTheWindow() throws {
        let meeting = try reviewedMeeting(on: 23, asking: [convio], skipped: ["Convio"])
        sut.show(meeting)

        sut.window?.cancelOperation(nil)

        XCTAssertEqual(sut.window?.isVisible, false)
        XCTAssertNil(controller.screen)
    }

    func testShowWithNothingToCheckKeepsTheWindowClosed() throws {
        sut.show(nil)

        XCTAssertEqual(sut.window?.isVisible, false)
        XCTAssertEqual(policies, [])
        XCTAssertEqual(activations, 0)
    }

    func testShowingAgainBringsTheOpenWindowForwardAlsoWhenThePageIsTheSame() throws {
        let meeting = try reviewedMeeting(on: 23, asking: [convio])
        sut.show(meeting)
        let before = activations

        sut.show(meeting)

        XCTAssertGreaterThan(activations, before)
        XCTAssertEqual(policies, [.regular])
    }

}
