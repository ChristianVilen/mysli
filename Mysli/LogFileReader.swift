import Foundation
import Darwin

protocol LogReading: Sendable {
    func rows(in interval: DateInterval?) async throws -> [LogRow]
}

extension LogReading {
    @concurrent
    func filteredRows(using filter: LogFilter, now: Date, launchDate: Date,
                      processID: Int32, calendar: Calendar) async throws -> [LogRow] {
        try Task.checkCancellation()
        let rows = try await rows(in: filter.range.interval(now: now, launchDate: launchDate, calendar: calendar))
        try Task.checkCancellation()
        return filter.rows(rows, now: now, launchDate: launchDate, processID: processID, calendar: calendar)
    }
}

actor LogFileReader: LogReading {
    private let folder: URL
    private let timeZone: TimeZone
    private let load: @Sendable (URL) throws -> Data
    private var cache: [URL: CachedFile] = [:]

    init(folder: URL, timeZone: TimeZone = .current,
         load: @escaping @Sendable (URL) throws -> Data = { try LogFileReader.readFile($0) }) {
        self.folder = folder
        self.timeZone = timeZone
        self.load = load
    }

    func rows(in interval: DateInterval?) throws -> [LogRow] {
        try Task.checkCancellation()
        let files = try LogFileEntry.list(in: folder, timeZone: timeZone)
        var current: [URL: CachedFile] = [:]
        var result: [LogRow] = []
        for file in files.sorted(by: { $0.url.lastPathComponent < $1.url.lastPathComponent }) {
            try Task.checkCancellation()
            guard interval.map({ file.day >= $0.start && file.day < $0.end }) ?? true else { continue }
            let url = file.url
            let stamp = file.stamp
            let entry: CachedFile
            if let cached = cache[url], cached.stamp == stamp {
                entry = cached
            } else {
                let data: Data
                do { data = try load(url) }
                catch let error as POSIXError where error.code == .ENOENT { continue }
                let text = String(decoding: data, as: UTF8.self)
                var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
                if lines.last == "" { lines.removeLast() }
                entry = CachedFile(stamp: stamp, rows: lines.enumerated().map {
                    LogRow(text: $0.element, day: file.day, id: .file(stamp.identity, line: $0.offset))
                })
            }
            current[url] = entry
            result.append(contentsOf: entry.rows)
        }
        cache = current
        return result
    }

    private struct CachedFile {
        let stamp: LogFileEntry.Stamp
        let rows: [LogRow]
    }

    private static func readFile(_ url: URL) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw systemError() }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw systemError() }
        guard info.st_mode & S_IFMT == S_IFREG else { throw POSIXError(.EINVAL) }
        var remaining = info.st_size
        var data = Data()
        while remaining > 0 {
            try Task.checkCancellation()
            guard let part = try handle.read(upToCount: Int(min(remaining, 65_536))), !part.isEmpty else { break }
            data.append(part)
            remaining -= Int64(part.count)
        }
        return data
    }

    private static func systemError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
