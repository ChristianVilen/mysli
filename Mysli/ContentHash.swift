import CryptoKit
import Foundation

/// SHA-256 content hashing, kept as a neutral namespace because two
/// unrelated features need the same answer: `ClipboardItem` uses it as its
/// dedupe key, and `ImageStore` records it for each screenshot it puts on
/// the clipboard. Both must hash identical bytes to identical strings, or a
/// deleted screenshot would not find its history row.
enum ContentHash {
    /// Lowercase hex digest of raw bytes.
    static func of(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Lowercase hex digest of a string's UTF-8 bytes.
    static func of(utf8 string: String) -> String {
        of(Data(string.utf8))
    }
}
