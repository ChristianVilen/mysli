import Foundation

struct SettingsSearchItem {
    enum Kind { case setting, page, guide }

    let page: SettingsPage
    let title: String
    var detail: String = ""
    var keywords: [String] = []
    var kind: Kind = .setting
}

enum SettingsSearch {
    static func matches(_ query: String, in items: [SettingsSearchItem]) -> [Int] {
        let terms = words(query)
        guard !terms.isEmpty else { return [] }
        return items.enumerated().compactMap { index, item -> (index: Int, score: Int)? in
            let title = words(item.title)
            let fields = [(title, 0), (words(item.keywords.joined(separator: " ")), 4),
                          (words(item.detail), 8), (words(item.page.title), 10)]
            var score = item.kind == .guide ? 12 : 0
            for term in terms {
                let costs = fields.compactMap { tokens, weight in
                    tokens.compactMap { cost(term, matching: $0).map { $0 + weight } }.min()
                }
                guard let best = costs.min() else { return nil }
                score += best
            }
            if title == terms { score -= 30 }
            else if title.starts(with: terms) { score -= 10 }
            return (index, score)
        }.sorted { lhs, rhs in
            lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score < rhs.score
        }.map(\.index)
    }

    private static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private static func cost(_ term: String, matching word: String) -> Int? {
        if term == word { return 0 }
        if word.hasPrefix(term) { return 2 }
        if term.count >= 4, word.count >= 4, oneEditApart(term, word) { return 24 }
        return nil
    }

    private static func oneEditApart(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs), b = Array(rhs)
        guard abs(a.count - b.count) <= 1 else { return false }
        let prefix = zip(a, b).prefix { $0 == $1 }.count
        if a.count == b.count {
            if a.dropFirst(prefix + 1).elementsEqual(b.dropFirst(prefix + 1)) { return true }
            return prefix + 1 < a.count && a[prefix] == b[prefix + 1] && a[prefix + 1] == b[prefix]
                && a.dropFirst(prefix + 2).elementsEqual(b.dropFirst(prefix + 2))
        }
        if a.count < b.count { return a.dropFirst(prefix).elementsEqual(b.dropFirst(prefix + 1)) }
        return a.dropFirst(prefix + 1).elementsEqual(b.dropFirst(prefix))
    }
}
