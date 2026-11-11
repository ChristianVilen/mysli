import Foundation

enum DictationText {
    case final(PasteText)
    case prose(PasteText)

    private static let fillers: Set<String> = ["um", "uh", "erm", "hmm"]

    var text: PasteText {
        switch self {
        case .final(let text), .prose(let text): return text
        }
    }

    static func local(_ heard: String, knownWords: KnownWordsList) -> Self? {
        let safe = String(String.UnicodeScalarView(heard.unicodeScalars.map {
            $0.properties.generalCategory == .control ? Unicode.Scalar(" ") : $0
        }))
        let formatted = DictationFormatting.apply(safe)
        let shell = removeShellFillers(safe)
        if isCommand(shell, hasFormatting: formatted.hasCommands) { return PasteText(shell).map(Self.final) }
        let corrector = knownWords.corrector
        let corrected = formatted.text.components(separatedBy: "\n")
            .map { corrector.correct($0).text }.joined(separator: "\n")
        guard let text = PasteText(cleanProse(corrected)) else { return nil }
        return text.value.rangeOfCharacter(from: .alphanumerics) == nil ? .final(text) : .prose(text)
    }

    static func accept(_ output: String, baseline: PasteText) -> PasteText? {
        guard !PasteText.containsUnsafeControls(output) else { return nil }
        let source = baseline.value
        var candidate = output.replacingOccurrences(of: "\r\n", with: "\n")
        if !source.contains("\n") { candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines) }
        let cleaned = cleanProse(candidate)
        let sourceLines = source.components(separatedBy: "\n")
        let resultLines = cleaned.components(separatedBy: "\n")
        guard sourceLines.count == resultLines.count else { return nil }
        let sourceWords = Set(words(source))
        for (before, after) in zip(sourceLines, resultLines) {
            let lineWords = Set(words(before))
            guard !words(after).contains(where: { sourceWords.contains($0) && !lineWords.contains($0) }),
                  acceptsLine(after, source: before) else { return nil }
        }
        return PasteText(cleaned)
    }

    private static func acceptsLine(_ cleaned: String, source: String) -> Bool {
        let before = words(source)
        let after = words(cleaned)
        if before.isEmpty { return cleaned == source }
        guard !after.isEmpty,
              after.count * 3 >= before.count,
              after.count <= (before.count * 3) / 2 + 1,
              cleaned.count * 5 >= source.count,
              cleaned.count <= source.count * 2 + 16 else { return false }
        var remaining = before.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        var shared = 0
        for word in after where remaining[word, default: 0] > 0 {
            remaining[word, default: 0] -= 1
            shared += 1
        }
        return shared * 3 >= before.count && shared * 10 >= after.count * 7
    }

    private static func isCommand(_ text: String, hasFormatting: Bool) -> Bool {
        let tokens = text.split(whereSeparator: \.isWhitespace)
        guard let first = tokens.first else { return false }
        let executable = first.lowercased()
        let commands: Set<String> = ["git", "rm", "mv", "cp", "cd", "ls", "echo", "printf", "cat", "curl",
            "wget", "ssh", "sudo", "env", "export", "npm", "pnpm", "yarn", "node", "python", "python3",
            "swift", "xcodebuild", "cargo", "go", "make", "docker", "kubectl", "brew", "chmod", "find", "rg"]
        if commands.contains(executable) || first.contains("/") || first.contains("=") { return true }
        let proseStarts: Set<String> = ["i", "we", "you", "he", "she", "it", "they", "the", "a", "an", "this",
            "that", "please", "hello", "hi", "thanks", "thank", "what", "why", "how", "when", "where", "who",
            "is", "are", "can", "could", "would", "should", "do", "does", "did", "run", "delete", "ignore"]
        let openingWord = executable.split(whereSeparator: { $0 == "'" || $0 == "’" }).first.map(String.init) ?? executable
        if proseStarts.contains(openingWord) { return false }
        if text.contains(where: { "`|;&<>\\\"".contains($0) }) { return true }
        if tokens.contains(where: { $0.hasPrefix("-") || $0.contains("=") || $0.contains("/") || $0.dropLast().contains(".") }) { return true }
        let proseVerbs: Set<String> = ["will", "would", "should", "could", "is", "are", "was", "were", "has", "have"]
        let clearProse = text.contains(where: { ".,?!".contains($0) })
            || tokens.contains(where: { proseVerbs.contains($0.lowercased()) })
        return !clearProse && !hasFormatting
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    private static func cleanProse(_ text: String) -> String {
        var result = text.components(separatedBy: "\n").map(cleanLine).joined(separator: "\n")
        if let last = result.last, last != "\n", !".,;:!?".contains(last) { result += "." }
        return result
    }

    private static func cleanLine(_ text: String) -> String {
        let quoted = DictationQuotes.ranges(in: text)
        let punctuation = CharacterSet(charactersIn: ",.!?")
        let tokens = text.split(whereSeparator: \.isWhitespace).filter { token in
            quoted.contains(where: { $0.overlaps(token.startIndex..<token.endIndex) })
                || !fillers.contains(token.lowercased().trimmingCharacters(in: punctuation))
        }
        var kept: [Substring] = []
        for token in tokens {
            if let previous = kept.last, previous.lowercased() == token.lowercased(),
               !quoted.contains(where: { $0.overlaps(token.startIndex..<token.endIndex) }) { continue }
            kept.append(token)
        }
        var result = kept.joined(separator: " ")
        guard let first = result.first else { return "" }
        if first.isLowercase { result.replaceSubrange(result.startIndex...result.startIndex, with: first.uppercased()) }
        return result
    }

    private static func removeShellFillers(_ text: String) -> String {
        var tokens: [String] = []
        var token = ""
        var quote: Character?
        var escaped = false
        for character in text {
            if escaped { token.append(character); escaped = false; continue }
            if character == "\\" { token.append(character); escaped = true; continue }
            if let current = quote {
                token.append(character)
                if character == current { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
                token.append(character)
            } else if character.isWhitespace {
                if !token.isEmpty { tokens.append(token); token = "" }
            } else { token.append(character) }
        }
        if !token.isEmpty { tokens.append(token) }
        let fillerPunctuation = CharacterSet(charactersIn: ",")
        return tokens.filter {
            !fillers.contains($0.lowercased().trimmingCharacters(in: fillerPunctuation))
        }.joined(separator: " ")
    }
}
