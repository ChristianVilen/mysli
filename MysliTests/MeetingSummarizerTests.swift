import XCTest
@testable import Mysli

final class MeetingSummarizerTests: XCTestCase {
    func testTheTypedNotesBlockAppearsOnlyWithNotesAndBeforeTheTranscript() throws {
        let notes = MeetingNoteDocument.summaryText([
            MeetingNoteEntry(time: .recording(754), text: "Mira checks access.", attachments: [UUID().uuidString + ".png"]),
        ])
        let prompt = SummaryPrompt.make(transcript: transcript, knownWords: .none, typedNotes: notes)

        let block = try XCTUnwrap(prompt.range(of: "\n<user-authored-meeting-notes>\n" + notes + "\n</user-authored-meeting-notes>\n"))
        let transcriptHeading = try XCTUnwrap(prompt.range(of: "\n\nTranscript:\n\n"))
        XCTAssertLessThan(block.upperBound, transcriptHeading.lowerBound)
        XCTAssertFalse(SummaryPrompt.make(transcript: transcript, knownWords: .none).contains("<user-authored-meeting-notes>"))
    }

    func testAnExplicitToolNeverFallsBackToTheOtherProvider() async {
        for (tool, cli) in [(SummaryTool.antigravity, SummaryCLI.antigravity), (.claude, .claude)] {
            let failing = FakeCommandRunner()
            failing.results[cli.rawValue] = .success(CommandResult(termination: .exited(2), stdout: "", stderr: "denied"))
            let failed = await summarizer(failing).summarize(transcript: transcript, knownWords: .none, tool: tool)
            XCTAssertEqual(failed, .failed([SummaryFailure(cli: cli, reason: .exited(status: 2, stderrTail: "denied"))]))
            XCTAssertEqual(failing.calls.map { $0.executable.lastPathComponent }, [cli.rawValue])

            let missing = FakeCommandRunner()
            let other = cli == .claude ? "agy" : "claude"
            let notInstalled = await summarizer(missing, installed: ["/opt/homebrew/bin/" + other])
                .summarize(transcript: transcript, knownWords: .none, tool: tool)
            XCTAssertEqual(notInstalled, .failed([SummaryFailure(cli: cli, reason: .notInstalled(searched: [
                "/opt/homebrew/bin/" + cli.rawValue,
                "/usr/local/bin/" + cli.rawValue,
                "/Users/test/.local/bin/" + cli.rawValue,
            ]))]))
            XCTAssertTrue(missing.calls.isEmpty)
        }
    }

    func testTheBackgroundBlockAppearsOnlyWithContextBeforeTheKnownWordsAndTheTranscript() throws {
        let background = "Project: Konvio\nPeople: Aino\n"
        let prompt = SummaryPrompt.make(transcript: transcript, knownWords: knownWords, context: background)

        let block = try XCTUnwrap(prompt.range(of: "\n<meeting-background>\n" + background + "\n</meeting-background>\n"))
        let knownWordsList = try XCTUnwrap(prompt.range(of: "\n\nKnown words:\n- Convio -> Konvio\n"))
        XCTAssertLessThan(block.upperBound, knownWordsList.lowerBound)
        XCTAssertTrue(prompt.hasSuffix("\n\nTranscript:\n\n" + transcript))
        XCTAssertFalse(SummaryPrompt.make(transcript: transcript, knownWords: knownWords).contains("<meeting-background>"))
    }

    func testContextReachesBothCLIsAndIsReadAgainForEachSummary() async throws {
        let file = try makeTemporaryDirectory().appendingPathComponent("context.md")
        try Data("Konvio background".utf8).write(to: file)
        let runner = FakeCommandRunner()
        runner.results["agy"] = .success(CommandResult(termination: .exited(1), stdout: "", stderr: ""))
        runner.results["claude"] = .reply(defaultNotes)
        let summarizer = Summarizer(runner: runner, home: URL(fileURLWithPath: "/Users/test"),
                                    isExecutable: { _ in true }, context: MeetingContextFile(url: { file }))
        _ = await summarizer.summarize(transcript: transcript, knownWords: knownWords, tool: .automatic)
        let expected = SummaryPrompt.make(transcript: transcript, knownWords: knownWords, context: "Konvio background")
        XCTAssertEqual(runner.calls.map { $0.input ?? $0.arguments.last }, [expected, expected])
        try Data("Changed background".utf8).write(to: file)
        _ = await summarizer.summarize(transcript: transcript, knownWords: .none, tool: .automatic)
        XCTAssertTrue(try XCTUnwrap(runner.calls.last?.input).contains("Changed background"))
    }

    func testEachFailureReadsAsOneLine() {
        let lines = [
            SummaryFailure(cli: .antigravity, reason: .notInstalled(searched: ["/opt/homebrew/bin/agy", "/usr/local/bin/agy"])),
            SummaryFailure(cli: .claude, reason: .couldNotLaunch("The file is not executable.")),
            SummaryFailure(cli: .antigravity, reason: .exited(status: 1, stderrTail: "error: authentication failed\nor timed out\n")),
            SummaryFailure(cli: .claude, reason: .exited(status: 2, stderrTail: "")),
            SummaryFailure(cli: .antigravity, reason: .timedOut),
            SummaryFailure(cli: .claude, reason: .emptyOutput),
        ].map(\.description)

        XCTAssertEqual(lines, [
            "agy was not found at /opt/homebrew/bin/agy, /usr/local/bin/agy",
            "claude could not start: The file is not executable.",
            "agy exited with status 1: error: authentication failed or timed out",
            "claude exited with status 2",
            "agy took too long and was stopped",
            "claude exited without writing a summary",
        ])
    }

    func testFailureLogsKeepToolAndReasonButHideLaunchDetailsAndToolOutput() {
        let failures = [
            SummaryFailure(cli: .claude, reason: .couldNotLaunch("private meeting content")),
            SummaryFailure(cli: .antigravity, reason: .exited(status: 7, stderrTail: "private transcript\nsecond line")),
        ]
        XCTAssertEqual(failures.map { $0.logMessage.text }, [
            "claude could not start: <private>",
            "agy exited with status 7: <private>",
        ])
        let composed: LogMessage = "Earlier failure: \(failures[1].logMessage)"
        XCTAssertEqual(composed.text, "Earlier failure: agy exited with status 7: <private>")
    }

    func testSummaryDocumentIsTheTitleAndTheTrimmedNotesWithoutAFooter() {
        let markdown = SummaryDocument.markdown(title: "Meeting on 2026-10-23 at 14:02", body: "\n## Summary\nShip Friday.\n\n")

        XCTAssertEqual(markdown, """
        # Meeting on 2026-10-23 at 14:02

        ## Summary
        Ship Friday.

        """)
    }

    private let transcript = "**[00:00:01] Them:** Let's ship on Friday"
    private let knownWords = KnownWordsList(markdown: "- Convio → **Konvio** ✓\n").relevant(to: "Ship Convio")
    private var prompt: String { SummaryPrompt.make(transcript: transcript, knownWords: knownWords) }

    private func summarizer(_ runner: FakeCommandRunner,
                            installed: Set<String> = ["/opt/homebrew/bin/agy", "/opt/homebrew/bin/claude"]) -> Summarizer {
        Summarizer(runner: runner, home: URL(fileURLWithPath: "/Users/test", isDirectory: true),
                   isExecutable: { installed.contains($0) })
    }

    func testThePreferredCLIWritesTheSummaryAndItsReviewBlockGivesTheSuspects() async {
        let runner = FakeCommandRunner()
        runner.results["agy"] = .success(CommandResult(
            termination: .exited(0), stdout: "## Summary\nShip Friday.\n\n```mysli-review\n\(askConvio)\n```\n", stderr: ""))

        let result = await summarizer(runner).summarize(transcript: transcript, knownWords: .none, tool: .automatic)

        XCTAssertEqual(result, .written(markdown: "## Summary\nShip Friday.", suspects: [suspect("Convio", quote: "Ask Convio.")],
                                        by: .antigravity, after: []))
        XCTAssertEqual(runner.calls.map(\.executable.path), ["/opt/homebrew/bin/agy"])
    }

    func testAReplyThatIsOnlyAReviewBlockCountsAsEmptyAndTheNextCLIWritesTheSummary() async {
        let runner = FakeCommandRunner()
        runner.results["agy"] = .success(CommandResult(termination: .exited(0), stdout: "```mysli-review\n\(askConvio)\n```\n", stderr: ""))
        runner.results["claude"] = .success(CommandResult(termination: .exited(0), stdout: "## Summary\nShip Friday.", stderr: ""))

        let result = await summarizer(runner).summarize(transcript: transcript, knownWords: .none, tool: .automatic)

        XCTAssertEqual(result, .written(markdown: "## Summary\nShip Friday.", suspects: [], by: .claude, after: [
            SummaryFailure(cli: .antigravity, reason: .emptyOutput),
        ]))
    }

    func testEachCLIGetsItsOwnArgumentsAndPromptAndTheUserToolsOnItsPath() async {
        let runner = FakeCommandRunner()
        runner.results["agy"] = .success(CommandResult(termination: .exited(1), stdout: "", stderr: ""))
        runner.results["claude"] = .success(CommandResult(termination: .exited(0), stdout: "## Summary", stderr: ""))

        _ = await summarizer(runner).summarize(transcript: transcript, knownWords: knownWords, tool: .automatic)

        XCTAssertEqual(runner.calls.map(\.arguments), [
            ["--sandbox", "--disable-slash-commands", "-p", prompt],
            ["-p", "--model", "sonnet", "--effort", "medium", "--tools", "", "--no-session-persistence", "--strict-mcp-config"],
        ])
        XCTAssertEqual(runner.calls.map(\.input), [nil, prompt], "claude reads the prompt on stdin")
        let searchPath = ["/opt/homebrew/bin", "/usr/local/bin", "/Users/test/.local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        XCTAssertEqual(runner.calls.map(\.searchPath), [searchPath, searchPath])
    }

    func testFallsBackToClaudeAndKeepsWhyAgyFailed() async {
        let runner = FakeCommandRunner()
        runner.results["agy"] = .success(CommandResult(termination: .exited(1), stdout: "", stderr: "authentication failed\n"))
        runner.results["claude"] = .success(CommandResult(termination: .exited(0), stdout: "## Summary\nShip Friday.\n", stderr: ""))

        let result = await summarizer(runner).summarize(transcript: transcript, knownWords: .none, tool: .automatic)

        XCTAssertEqual(result, .written(markdown: "## Summary\nShip Friday.", suspects: [], by: .claude, after: [
            SummaryFailure(cli: .antigravity, reason: .exited(status: 1, stderrTail: "authentication failed\n")),
        ]))
    }

    func testAMissingCLIIsSkippedWithThePathsSearched() async {
        let runner = FakeCommandRunner()
        runner.results["claude"] = .success(CommandResult(termination: .exited(0), stdout: "## Summary", stderr: ""))

        let result = await summarizer(runner, installed: ["/Users/test/.local/bin/claude"]).summarize(transcript: transcript, knownWords: .none, tool: .automatic)

        XCTAssertEqual(result, .written(markdown: "## Summary", suspects: [], by: .claude, after: [
            SummaryFailure(cli: .antigravity, reason: .notInstalled(searched: [
                "/opt/homebrew/bin/agy", "/usr/local/bin/agy", "/Users/test/.local/bin/agy",
            ])),
        ]))
        XCTAssertEqual(runner.calls.map(\.executable.path), ["/Users/test/.local/bin/claude"])
    }

    func testWhenEveryCLIFailsEachFailureIsListedInOrder() async {
        let runner = FakeCommandRunner()
        runner.results["agy"] = .success(CommandResult(termination: .exited(0), stdout: " \n", stderr: ""))
        runner.results["claude"] = .success(CommandResult(termination: .timedOut, stdout: "", stderr: ""))

        let result = await summarizer(runner).summarize(transcript: transcript, knownWords: .none, tool: .automatic)

        XCTAssertEqual(result, .failed([
            SummaryFailure(cli: .antigravity, reason: .emptyOutput),
            SummaryFailure(cli: .claude, reason: .timedOut),
        ]))
    }

    func testALaunchErrorAndALongStderrAreReported() async {
        let runner = FakeCommandRunner()
        runner.results["agy"] = .failure(CocoaError(.fileReadNoPermission))
        runner.results["claude"] = .success(CommandResult(
            termination: .exited(2), stdout: "", stderr: String(repeating: "x", count: 700) + String(repeating: "y", count: 300)))

        let result = await summarizer(runner).summarize(transcript: transcript, knownWords: .none, tool: .automatic)

        XCTAssertEqual(result, .failed([
            SummaryFailure(cli: .antigravity, reason: .couldNotLaunch(CocoaError(.fileReadNoPermission).localizedDescription)),
            SummaryFailure(cli: .claude, reason: .exited(status: 2, stderrTail: String(repeating: "y", count: 300))),
        ]))
    }

    func testWithoutKnownWordsThePromptAsksForTheReviewBlockBeforeTheTranscript() throws {
        let prompt = SummaryPrompt.make(transcript: transcript, knownWords: .none)

        XCTAssertFalse(prompt.contains("Known words:"))
        XCTAssertFalse(prompt.contains("\nCorrect as heard:"))
        XCTAssertFalse(prompt.contains("Do not list a word from the lists above."))
        let review = try XCTUnwrap(prompt.range(of: "add one fenced code block with the info string mysli-review."))
        for key in ["heard", "suggestion", "kind", "quote", "reason"] {
            XCTAssertTrue(prompt[review.upperBound...].contains("\n\"\(key)\": "), key)
        }
        let transcriptHeading = try XCTUnwrap(prompt.range(of: "\n\nTranscript:\n\n"))
        XCTAssertLessThan(review.upperBound, transcriptHeading.lowerBound)
        XCTAssertTrue(prompt.hasSuffix("\n\nTranscript:\n\n" + transcript))
    }

    /// The list has notes, dates, and ✓ marks, and words that the meeting does not mention. None of
    /// them reach the CLI.
    func testWithKnownWordsThePromptListsOnlyTheFormsOfTheRelevantWords() {
        let list = KnownWordsList(markdown: KnownWordsListTests.fixture + """

        ## Correct as heard
        - **Aino** (correct as heard; added 2026-10-28)
        - Maikki
        - Ilona
        """)
        let relevant = list.relevant(to: "Kon Vio and Yuri met Aino and Maikki about Quorix.")

        let prompt = SummaryPrompt.make(transcript: transcript, knownWords: relevant)

        XCTAssertTrue(prompt.contains("""


        Known words:
        - Convio / Konvia / Gonvio / Kon Vio -> Konvio
        - QRX -> Quorix
        - Yuri -> Jyri

        Correct as heard: Aino, Maikki


        """), prompt)
        for leftOut in ["✓", "2026-", "provisional", "Brytlane", "Ilona"] {
            XCTAssertFalse(prompt.contains(leftOut), leftOut)
        }
    }

    func testWithOnlyCorrectAsHeardWordsThePromptHasNoKnownWordsList() {
        let relevant = KnownWordsList(markdown: "## Correct as heard\n- Aino\n").relevant(to: "Aino agreed.")

        let prompt = SummaryPrompt.make(transcript: transcript, knownWords: relevant)

        XCTAssertFalse(prompt.contains("Known words:"), prompt)
        XCTAssertEqual(prompt.components(separatedBy: "\n\nCorrect as heard: Aino\n\n").count, 2, prompt)
        XCTAssertTrue(prompt.contains("Do not list a word from the lists above."), prompt)
    }

    private func suspect(_ heard: String, quote: String, suggestion: String? = nil, kind: WordKind = .other,
                         reason: String? = nil) -> SuspectWord {
        SuspectWord(heard: heard, suggestion: suggestion, kind: kind, quote: quote, reason: reason)
    }

    private let askConvio = #"[{"heard": "Convio", "quote": "Ask Convio."}]"#

    func testTheReviewBlockIsRemovedFromTheNotesAndItsItemsBecomeSuspects() {
        let reply = SummaryReply.parse("""
        ## Summary
        Ship Friday.

        ```mysli-review
        [{"heard": "Convio", "suggestion": "Konvio", "kind": "company", "quote": "We should ask Convio.", "reason": "spelled three ways"},
         {"heard": "Yuri", "suggestion": null, "kind": "person", "quote": "Yuri has the numbers.", "reason": "a name"}]
        ```

        """)

        XCTAssertEqual(reply, SummaryReply(notes: "## Summary\nShip Friday.", suspects: [
            suspect("Convio", quote: "We should ask Convio.", suggestion: "Konvio", kind: .company, reason: "spelled three ways"),
            suspect("Yuri", quote: "Yuri has the numbers.", kind: .person, reason: "a name"),
        ]))
    }

    func testAReplyWithoutABlockKeepsItsNotesAndHasNoSuspects() {
        let notes = "## Summary\nShip Friday.\n\n```json\n[{\"heard\": \"Convio\", \"quote\": \"Ask Convio.\"}]\n```"

        XCTAssertEqual(SummaryReply.parse("\n" + notes + "\n\n"), SummaryReply(notes: notes, suspects: []))
    }

    func testABlockWithBrokenJSONIsRemovedAndGivesNoSuspects() {
        for block in [#"[{"heard": "Convio", "#, #"{"heard": "Convio", "quote": "Ask Convio."}"#, "Nothing looks wrong.", ""] {
            let reply = SummaryReply.parse("## Summary\nShip Friday.\n```mysli-review\n\(block)\n```\n")

            XCTAssertEqual(reply, SummaryReply(notes: "## Summary\nShip Friday.", suspects: []), block)
        }
    }

    func testAnUnclosedBlockIsRemovedToTheEndOfTheReply() {
        let reply = SummaryReply.parse("## Summary\nShip Friday.\n\n```mysli-review\n\(askConvio)\n")

        XCTAssertEqual(reply, SummaryReply(notes: "## Summary\nShip Friday.", suspects: [suspect("Convio", quote: "Ask Convio.")]))
    }

    func testWithTwoBlocksOnlyTheLastCountsAndNeitherStaysInTheNotes() {
        let reply = SummaryReply.parse("""
        ## Summary
        ```mysli-review
        [{"heard": "Brightlane", "quote": "Brightlane called."}]
        ```
        Ship Friday.
        ```mysli-review
        \(askConvio)
        ```
        """)

        XCTAssertEqual(reply, SummaryReply(notes: "## Summary\nShip Friday.", suspects: [suspect("Convio", quote: "Ask Convio.")]))
    }

    func testTildeFencesAndAnyCaseOfTheInfoStringStartABlock() {
        for (opening, closing) in [("~~~mysli-review", "~~~"), ("```MYSLI-REVIEW", "```"), ("  ```  Mysli-Review ", " ```")] {
            let reply = SummaryReply.parse("## Summary\nShip Friday.\n\(opening)\n\(askConvio)\n\(closing)\n")

            XCTAssertEqual(reply, SummaryReply(notes: "## Summary\nShip Friday.", suspects: [suspect("Convio", quote: "Ask Convio.")]),
                           opening)
        }
    }

    func testItemsOfTheWrongShapeAreSkippedAndAtMostTenAreRead() {
        let skipped = [
            #"{"quote": "Ask Convio."}"#,
            #"{"heard": "Convio"}"#,
            #"{"heard": 7, "quote": "Ask Convio."}"#,
            #"{"heard": " ", "quote": "Ask Convio."}"#,
            #""Convio""#,
        ]
        let kept = [
            #"{"heard": "Convio", "quote": "Ask Convio.", "kind": "vendor", "suggestion": ""}"#,
            #"{"heard": "Yuri", "quote": "Yuri agreed.", "suggestion": "Jyri\nor Juri", "reason": " "}"#,
            #"{"heard": "Brightlane", "quote": "Brightlane called.", "suggestion": " Brytlane ", "kind": "company"}"#,
        ] + (1...12).map { #"{"heard": "Word\#($0)", "quote": "Word\#($0) was said.", "kind": "term"}"# }

        let reply = SummaryReply.parse("## Summary\n```mysli-review\n[\((skipped + kept).joined(separator: ",\n"))]\n```")

        XCTAssertEqual(Array(reply.suspects.prefix(3)), [
            suspect("Convio", quote: "Ask Convio."),
            suspect("Yuri", quote: "Yuri agreed."),
            suspect("Brightlane", quote: "Brightlane called.", suggestion: "Brytlane", kind: .company),
        ])
        XCTAssertEqual(reply.suspects.dropFirst(3).map(\.heard), (1...7).map { "Word\($0)" })
        XCTAssertEqual(reply.suspects.last?.kind, .term)
    }
}
