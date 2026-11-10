import Foundation

enum DictationText {
    static func local(_ heard: String, knownWords: KnownWordsList) -> PasteText? {
        let safe = String(String.UnicodeScalarView(heard.unicodeScalars.map {
            $0.properties.generalCategory == .control ? Unicode.Scalar(" ") : $0
        }))
        let withoutFillers = removeFillers(safe)
        if isCommand(withoutFillers) { return PasteText(withoutFillers) }
        return PasteText(cleanProse(knownWords.corrector.correct(withoutFillers).text))
    }

    static func accept(_ output: String, baseline: PasteText) -> PasteText? {
        guard !PasteText.containsUnsafeControls(output) else { return nil }
        let source = baseline.value
        if isCommand(source) {
            guard !output.contains(where: \.isNewline),
                  removeFillers(output) == source else { return nil }
            return baseline
        }
        let cleaned = cleanProse(output)
        let before = words(source)
        let after = words(cleaned)
        guard !before.isEmpty, !after.isEmpty,
              after.count * 3 >= before.count,
              after.count <= (before.count * 3) / 2 + 1,
              cleaned.count * 5 >= source.count,
              cleaned.count <= source.count * 2 + 16 else { return nil }
        var remaining = before.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        var shared = 0
        for word in after where remaining[word, default: 0] > 0 {
            remaining[word, default: 0] -= 1
            shared += 1
        }
        guard shared * 3 >= before.count, shared * 10 >= after.count * 7 else { return nil }
        return PasteText(cleaned)
    }

    static func isCommand(_ text: String) -> Bool {
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
        return !clearProse
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    private static func cleanProse(_ text: String) -> String {
        let tokens = removeFillers(text, quotes: .prose).split(whereSeparator: \.isWhitespace).map(String.init)
        var kept: [String] = []
        for token in tokens {
            if let previous = kept.last, previous.lowercased() == token.lowercased() { continue }
            kept.append(token)
        }
        var result = kept.joined(separator: " ")
        guard let first = result.first else { return "" }
        if first.isLowercase { result.replaceSubrange(result.startIndex...result.startIndex, with: first.uppercased()) }
        if let last = result.last, !".!?".contains(last) { result += "." }
        return result
    }

    private enum QuoteContext { case shell, prose }

    private static func removeFillers(_ text: String, quotes: QuoteContext = .shell) -> String {
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
            } else if character == "'", quotes == .prose, token.last?.isLetter == true {
                token.append(character)
            } else if character == "\"" || character == "'" {
                quote = character
                token.append(character)
            } else if character.isWhitespace {
                if !token.isEmpty { tokens.append(token); token = "" }
            } else { token.append(character) }
        }
        if !token.isEmpty { tokens.append(token) }
        let fillers: Set<String> = ["um", "uh", "erm", "hmm"]
        let fillerPunctuation = CharacterSet(charactersIn: quotes == .prose ? ",.!?" : ",")
        return tokens.filter {
            !fillers.contains($0.lowercased().trimmingCharacters(in: fillerPunctuation))
        }.joined(separator: " ")
    }
}
