import XCTest
@testable import KuKa

final class MeetingSummarizerTests: XCTestCase {
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

    func testSummaryDocumentNamesTheCLIAndWhyEarlierOnesWereSkipped() {
        let markdown = SummaryDocument.markdown(
            title: "Meeting on 2026-10-23 at 14:02",
            body: "\n## Summary\nShip Friday.\n\n",
            by: .claude,
            after: [SummaryFailure(cli: .antigravity, reason: .exited(status: 1, stderrTail: "authentication failed"))])

        XCTAssertEqual(markdown, """
        # Meeting on 2026-10-23 at 14:02

        ## Summary
        Ship Friday.

        ---

        Summary by `claude`. Tried first:

        - agy exited with status 1: authentication failed

        """)
    }

    func testSummaryDocumentFromTheFirstCLIHasNoSkippedList() {
        let markdown = SummaryDocument.markdown(title: "Standup", body: "## Summary\nAll good.", by: .antigravity, after: [])

        XCTAssertEqual(markdown, """
        # Standup

        ## Summary
        All good.

        ---

        Summary by `agy`.

        """)
    }

    private let transcript = "**[00:00:01] Them:** Let's ship on Friday"
    private var prompt: String { SummaryPrompt.make(transcript: transcript) }

    private func summarizer(_ runner: FakeCommandRunner,
                            installed: Set<String> = ["/opt/homebrew/bin/agy", "/opt/homebrew/bin/claude"]) -> Summarizer {
        Summarizer(runner: runner, home: URL(fileURLWithPath: "/Users/test", isDirectory: true),
                   isExecutable: { installed.contains($0) })
    }

    func testThePreferredCLIWritesTheSummary() async {
        let runner = FakeCommandRunner()
        runner.results["agy"] = .success(CommandResult(termination: .exited(0), stdout: "## Summary\nShip Friday.", stderr: ""))

        let result = await summarizer(runner).summarize(transcript: transcript)

        XCTAssertEqual(result, .written(markdown: "## Summary\nShip Friday.", by: .antigravity, after: []))
        XCTAssertEqual(runner.calls.map(\.executable.path), ["/opt/homebrew/bin/agy"])
    }

    func testEachCLIGetsItsOwnArgumentsAndPromptAndTheUserToolsOnItsPath() async {
        let runner = FakeCommandRunner()
        runner.results["agy"] = .success(CommandResult(termination: .exited(1), stdout: "", stderr: ""))
        runner.results["claude"] = .success(CommandResult(termination: .exited(0), stdout: "## Summary", stderr: ""))

        _ = await summarizer(runner).summarize(transcript: transcript)

        XCTAssertEqual(runner.calls.map(\.arguments), [
            ["--sandbox", "--disable-slash-commands", "-p", prompt],
            ["-p", "--tools", "", "--no-session-persistence", "--strict-mcp-config"],
        ])
        XCTAssertEqual(runner.calls.map(\.input), [nil, prompt], "claude reads the prompt on stdin")
        let searchPath = ["/opt/homebrew/bin", "/usr/local/bin", "/Users/test/.local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        XCTAssertEqual(runner.calls.map(\.searchPath), [searchPath, searchPath])
    }

    func testFallsBackToClaudeAndKeepsWhyAgyFailed() async {
        let runner = FakeCommandRunner()
        runner.results["agy"] = .success(CommandResult(termination: .exited(1), stdout: "", stderr: "authentication failed\n"))
        runner.results["claude"] = .success(CommandResult(termination: .exited(0), stdout: "## Summary\nShip Friday.\n", stderr: ""))

        let result = await summarizer(runner).summarize(transcript: transcript)

        XCTAssertEqual(result, .written(markdown: "## Summary\nShip Friday.\n", by: .claude, after: [
            SummaryFailure(cli: .antigravity, reason: .exited(status: 1, stderrTail: "authentication failed\n")),
        ]))
    }

    func testAMissingCLIIsSkippedWithThePathsSearched() async {
        let runner = FakeCommandRunner()
        runner.results["claude"] = .success(CommandResult(termination: .exited(0), stdout: "## Summary", stderr: ""))

        let result = await summarizer(runner, installed: ["/Users/test/.local/bin/claude"]).summarize(transcript: transcript)

        XCTAssertEqual(result, .written(markdown: "## Summary", by: .claude, after: [
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

        let result = await summarizer(runner).summarize(transcript: transcript)

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

        let result = await summarizer(runner).summarize(transcript: transcript)

        XCTAssertEqual(result, .failed([
            SummaryFailure(cli: .antigravity, reason: .couldNotLaunch(CocoaError(.fileReadNoPermission).localizedDescription)),
            SummaryFailure(cli: .claude, reason: .exited(status: 2, stderrTail: String(repeating: "y", count: 300))),
        ]))
    }

    func testPromptEndsWithTheTranscript() {
        let prompt = SummaryPrompt.make(transcript: "**[00:00:01] Them:** Let's ship on Friday")

        XCTAssertTrue(prompt.hasSuffix("Transcript:\n\n**[00:00:01] Them:** Let's ship on Friday"), prompt)
    }
}
