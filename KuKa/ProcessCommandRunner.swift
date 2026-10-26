import Foundation

struct CommandResult: Equatable {
    enum Termination: Equatable {
        case exited(Int32)
        case timedOut
    }
    let termination: Termination
    let stdout: String
    let stderr: String
}

protocol CommandRunning {
    /// `input` becomes the child's stdin; without it, stdin is at end of file.
    /// `searchPath` is the child's whole `PATH`, in order.
    func run(executable: URL, arguments: [String], input: String?, searchPath: [String],
             timeout: Duration) async throws -> CommandResult
}

final class ProcessCommandRunner: CommandRunning {
    private let killGrace: Duration

    init(killGrace: Duration = .seconds(5)) {
        self.killGrace = killGrace
    }

    @concurrent
    func run(executable: URL, arguments: [String], input: String?, searchPath: [String],
             timeout: Duration) async throws -> CommandResult {
        let fileManager = FileManager.default
        let runFolder = fileManager.temporaryDirectory
            .appendingPathComponent("ku-ka-summary-\(UUID().uuidString)", isDirectory: true)
        let emptyWorkingDirectory = runFolder.appendingPathComponent("work", isDirectory: true)
        try fileManager.createDirectory(at: emptyWorkingDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: runFolder) }
        let stdoutURL = runFolder.appendingPathComponent("stdout")
        let stderrURL = runFolder.appendingPathComponent("stderr")

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        // Files, not pipes: a pipe holds 64 KB, and a child that fills it
        // blocks until someone reads, so pipes would need reading while the
        // child runs. The same holds for stdin in the other direction.
        let stdinFile = try input.map { try Self.file(containing: $0, at: runFolder.appendingPathComponent("stdin")) }
        let stdoutFile = try Self.emptyFile(at: stdoutURL)
        let stderrFile = try Self.emptyFile(at: stderrURL)
        defer {
            try? stdinFile?.close()
            try? stdoutFile.close()
            try? stderrFile.close()
        }
        process.standardInput = stdinFile ?? FileHandle.nullDevice
        process.standardOutput = stdoutFile
        process.standardError = stderrFile
        // So the CLI reads no project files or instructions (such as
        // CLAUDE.md) and asks for no workspace trust.
        process.currentDirectoryURL = emptyWorkingDirectory
        process.environment = ProcessInfo.processInfo.environment
            .merging(["PATH": searchPath.joined(separator: ":")]) { $1 }
        let (exits, exited) = AsyncStream<Void>.makeStream()
        process.terminationHandler = { _ in exited.finish() }

        try Task.checkCancellation()
        try process.run()
        let timer = Task {
            do { try await Task.sleep(for: timeout) } catch { return false }
            stop(process)
            return true
        }
        await withTaskCancellationHandler {
            for await _ in exits {}
        } onCancel: {
            stop(process)
        }
        timer.cancel()
        try Task.checkCancellation()

        let termination: CommandResult.Termination = await timer.value ? .timedOut : .exited(process.terminationStatus)
        return CommandResult(termination: termination,
                             stdout: String(decoding: try Data(contentsOf: stdoutURL), as: UTF8.self),
                             stderr: String(decoding: try Data(contentsOf: stderrURL), as: UTF8.self))
    }

    /// SIGTERM lets the CLI clean up. SIGKILL follows for a child that ignores it.
    private func stop(_ process: Process) {
        process.terminate()
        let grace = killGrace
        Task {
            try? await Task.sleep(for: grace)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    private static func file(containing text: String, at url: URL) throws -> FileHandle {
        try Data(text.utf8).write(to: url)
        return try FileHandle(forReadingFrom: url)
    }

    private static func emptyFile(at url: URL) throws -> FileHandle {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try FileHandle(forWritingTo: url)
    }
}
