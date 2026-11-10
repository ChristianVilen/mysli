import AppKit
import ApplicationServices

protocol DictationContextNode {
    var role: String? { get }
    var subrole: String? { get }
    var protected: Bool? { get }
    var selection: CFRange? { get }
    func string(for range: CFRange) -> String?
}

protocol DictationContextAccessibility {
    var trusted: Bool { get }
    func focusedNode(pid: Int32) -> (any DictationContextNode)?
}

struct DictationFrontApp {
    let pid: Int32
    let name: String

    @MainActor
    static func current() -> Self? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return Self(pid: app.processIdentifier, name: app.localizedName ?? "")
    }
}

struct DictationContext {
    private let knownWords: KnownWordsFile
    private let nearbyText: @MainActor () -> Bool
    private let frontApp: @MainActor () -> DictationFrontApp?
    private let accessibility: any DictationContextAccessibility

    init(knownWords: KnownWordsFile, nearbyText: @escaping @MainActor () -> Bool,
         frontApp: @escaping @MainActor () -> DictationFrontApp? = { DictationFrontApp.current() },
         accessibility: any DictationContextAccessibility = DictationAXContext()) {
        self.knownWords = knownWords
        self.nearbyText = nearbyText
        self.frontApp = frontApp
        self.accessibility = accessibility
    }

    @concurrent
    func prepareText(_ heard: String) async -> DictationPolishRequest? {
        let list = knownWords.read()
        guard let local = DictationText.local(heard, knownWords: list) else { return nil }
        var seen = Set<String>()
        let spellings = (list.words.map(\.right) + list.correctAsHeard.map(\.text))
            .filter { seen.insert($0).inserted }
        let app = await frontApp()
        let sharesText = await nearbyText()
        var preceding: String?
        if sharesText, let app, accessibility.trusted,
           let node = accessibility.focusedNode(pid: app.pid) {
            preceding = Self.precedingText(in: node)
        }
        return DictationPolishRequest(heardText: heard, localText: local, correctSpellings: spellings,
                                     appName: app?.name ?? "", precedingText: preceding)
    }

    static func precedingText(in node: any DictationContextNode) -> String? {
        guard let role = node.role, ["AXTextField", "AXTextArea"].contains(role),
              let subrole = node.subrole, subrole != "AXSecureTextField",
              node.protected == false,
              let selection = node.selection,
              selection.location >= 0, selection.length >= 0,
              selection.length <= Int.max - selection.location else { return nil }
        let count = min(selection.location, 500)
        guard count > 0 else { return nil }
        let start = selection.location - count
        guard let text = node.string(for: CFRange(location: start, length: count)),
              text.utf16.count == count,
              !text.unicodeScalars.contains(where: { $0.value == 0xFFFD }) else { return nil }
        // A range can start inside a grapheme. Discard that first cluster when truncated.
        let prefix = start > 0 ? String(text.dropFirst()) : text
        return prefix.isEmpty ? nil : String(prefix.suffix(500))
    }
}

private struct DictationAXContext: DictationContextAccessibility {
    var trusted: Bool { AXIsProcessTrusted() }

    func focusedNode(pid: Int32) -> (any DictationContextNode)? {
        let app = AXUIElementCreateApplication(pid)
        guard AXUIElementSetMessagingTimeout(app, 0.1) == .success else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(value, to: AXUIElement.self)
        guard AXUIElementSetMessagingTimeout(element, 0.1) == .success else { return nil }
        return DictationAXNode(element: element)
    }
}

struct DictationAXNode: DictationContextNode {
    private let attribute: (String) -> CFTypeRef?
    private let readString: (CFRange) -> String?

    init(attribute: @escaping (String) -> CFTypeRef?, readString: @escaping (CFRange) -> String? = { _ in nil }) {
        self.attribute = attribute
        self.readString = readString
    }

    init(element: AXUIElement) {
        self.init(attribute: { name in
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value
        }, readString: { range in
            var range = range
            guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
            var value: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                             parameter, &value) == .success else { return nil }
            return value as? String
        })
    }
    var role: String? { attribute(kAXRoleAttribute) as? String }
    var subrole: String? { attribute(kAXSubroleAttribute) as? String }
    var protected: Bool? {
        guard let value = attribute(NSAccessibility.Attribute.containsProtectedContent.rawValue),
              CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return (value as? Bool)
    }
    var selection: CFRange? {
        guard let value = attribute(kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    func string(for range: CFRange) -> String? {
        readString(range)
    }
}
