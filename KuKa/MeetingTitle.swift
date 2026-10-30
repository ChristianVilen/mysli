import Foundation

enum MeetingTitle {
    static func normalized(_ text: String) -> String? {
        let line = text.components(separatedBy: .whitespacesAndNewlines.union(.controlCharacters))
            .filter { !$0.isEmpty }.joined(separator: " ")
        let bounded = String(line.prefix(300)).trimmingCharacters(in: .whitespaces)
        return bounded.isEmpty ? nil : bounded
    }

    static func heading(_ text: String) -> String {
        let line = normalized(text) ?? ""
        return line.reduce(into: "") { result, character in
            if "\\`*_{}[]<>()#+!|&".contains(character) { result.append("\\") }
            result.append(character)
        }
    }
}
