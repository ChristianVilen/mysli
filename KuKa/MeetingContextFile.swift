import Foundation
import Darwin

struct MeetingContextFile {
    private static let maximumBytes = 16_384
    private let url: () -> URL?

    init(url: @escaping () -> URL?) {
        self.url = url
    }

    func read() -> String? {
        guard let url = url() else { return nil }
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno != ENOENT { omit(url, reason: "could not open file") }
            return nil
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            omit(url, reason: "could not inspect file")
            return nil
        }
        guard info.st_mode & S_IFMT == S_IFREG else {
            omit(url, reason: "not a regular file")
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: Self.maximumBytes + 1)
        var count = 0
        while count < bytes.count {
            let readCount = bytes.withUnsafeMutableBytes { buffer in
                Darwin.read(descriptor, buffer.baseAddress!.advanced(by: count), buffer.count - count)
            }
            if readCount == 0 { break }
            if readCount < 0 {
                if errno == EINTR { continue }
                omit(url, reason: "could not read file")
                return nil
            }
            count += readCount
        }
        guard count <= Self.maximumBytes else {
            omit(url, reason: "larger than 16 KiB")
            return nil
        }
        guard let text = String(validating: bytes.prefix(count), as: UTF8.self) else {
            omit(url, reason: "not UTF-8 text")
            return nil
        }
        guard !text.utf8.contains(0) else {
            omit(url, reason: "contains a NUL byte")
            return nil
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    private func omit(_ url: URL, reason: String) {
        Log.meeting.error("Meeting context omitted at \(url.path, privacy: .public): \(reason, privacy: .public).")
    }
}
