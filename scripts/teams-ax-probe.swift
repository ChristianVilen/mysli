import AppKit
import ApplicationServices

struct ProbeRequest {
    let pid: Int32
    let title: String
    let path: [Int]
    let attribute: String?
    static func parse(_ args: [String]) throws -> ProbeRequest {
        var options: [String: String] = [:]
        var confirmed = false
        var i = 0
        while i < args.count {
            let key = args[i]
            if key == "--confirm" && !confirmed { confirmed = true; i += 1; continue }
            guard ["--pid", "--window-title", "--mode", "--path", "--attribute"].contains(key),
                  options[key] == nil, i + 1 < args.count else { throw ProbeFailure.message("invalid arguments") }
            options[key] = args[i + 1]
            i += 2
        }
        guard confirmed, let pidText = options["--pid"], let pid = Int32(pidText), pid > 0,
              let title = options["--window-title"], !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let mode = options["--mode"], ["structure", "read"].contains(mode),
              let pathText = options["--path"] else { throw ProbeFailure.message("invalid arguments") }
        let parts = pathText.isEmpty ? [] : pathText.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 30 else { throw ProbeFailure.message("path too long") }
        var path: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let index = Int(part), index >= 0, index < Int(Int32.max) else { throw ProbeFailure.message("invalid path") }
            path.append(index)
        }
        let attribute = options["--attribute"]
        let allowed = ["AXRole", "AXSubrole", "AXIdentifier", "AXDOMClassList", "AXTitle", "AXDescription", "AXValue", "AXSelected"]
        guard (mode == "structure" && attribute == nil) ||
                (mode == "read" && !path.isEmpty && attribute.map(allowed.contains) == true)
        else { throw ProbeFailure.message("invalid mode or attribute") }
        return ProbeRequest(pid: pid, title: title, path: path, attribute: attribute)
    }
}

enum ProbeFailure: Error {
    case message(String)
    case ax(Int32)
}

protocol ProbeAX {
    associatedtype Node
    func bundleID(pid: Int32) -> String?
    func trusted() -> Bool
    func focusedWindow(pid: Int32) throws -> Node
    func value(_ node: Node, _ attribute: String) throws -> Any
    func attributes(_ node: Node) throws -> [String]
    func children(_ node: Node, start: Int, count: Int) throws -> [Node]
    func clock() -> UInt64
}

func probe<AX: ProbeAX>(_ args: [String], ax: AX) -> String {
    if args == ["--help"] { return probeHelp }
    do {
        let request = try ProbeRequest.parse(args)
        guard ax.bundleID(pid: request.pid) == "com.microsoft.teams2" else { throw ProbeFailure.message("PID is not Teams") }
        guard ax.trusted() else { throw ProbeFailure.message("Accessibility permission required") }
        var node = try ax.focusedWindow(pid: request.pid)
        guard let title = try ax.value(node, "AXTitle") as? String, title == request.title
        else { throw ProbeFailure.message("focused window does not match") }
        for index in request.path {
            let children = try ax.children(node, start: index, count: 1)
            guard children.count == 1 else { throw ProbeFailure.message("path index out of range") }
            node = children[0]
        }
        let role = try ax.value(node, "AXRole")
        guard let roleText = role as? String else { throw ProbeFailure.message("invalid role") }
        if let attribute = request.attribute {
            guard !["AXTextField", "AXTextArea", "AXSecureTextField"].contains(roleText)
            else { throw ProbeFailure.message("text input node") }
            let before = ax.clock()
            let value = try ax.value(node, attribute)
            let after = ax.clock()
            return "before_host_ticks=\(before)\nafter_host_ticks=\(after)\n\(attribute)=\(try formatValue(value))"
        }
        var lines = ["role=\(try formatValue(role))", "attributes=\(try formatValue(ax.attributes(node)))"]
        let children = try ax.children(node, start: 0, count: 40)
        for (index, child) in children.prefix(40).enumerated() {
            let path = (request.path + [index]).map(String.init).joined(separator: ".")
            lines.append("\(path) role=\(try formatValue(ax.value(child, "AXRole")))")
        }
        return lines.joined(separator: "\n")
    } catch ProbeFailure.ax(let code) {
        return "AX error \(code)"
    } catch ProbeFailure.message(let message) {
        return "refused: \(message)"
    } catch {
        return "refused: unexpected failure"
    }
}

func formatValue(_ value: Any) throws -> String {
    let object: Any
    if let text = value as? String {
        guard text.utf8.count <= 2048 else { throw ProbeFailure.message("attribute value exceeds output limit") }
        object = text
    } else if let texts = value as? [String] {
        guard texts.count <= 128, texts.reduce(0, { $0 + $1.utf8.count }) <= 2048
        else { throw ProbeFailure.message("attribute value exceeds output limit") }
        object = texts
    } else if let number = value as? NSNumber {
        guard number.doubleValue.isFinite else { throw ProbeFailure.message("unsupported attribute value") }
        object = number
    } else {
        throw ProbeFailure.message("unsupported attribute value")
    }
    let data = try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed, .sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

let probeHelp = """
Read-only Teams AX snapshot. No call is started or recorded.
Usage: teams-ax-probe --pid PID --window-title EXACT_TITLE --confirm --mode structure --path ''
       teams-ax-probe --pid PID --window-title EXACT_TITLE --confirm --mode read --path 0.2 --attribute AXRole
Find the participant node with structure before reading it. Paths are temporary diagnostic locators.
Structure prints one node and up to 40 immediate children. Paths have at most 30 indices.
Read accepts AXRole, AXSubrole, AXIdentifier, AXDOMClassList, AXTitle, AXDescription, AXValue, AXSelected.
Read refuses text inputs and complex values. Strings and string arrays are limited to 2048 UTF-8 bytes.
Host timestamps use mach_absolute_time ticks. Each AX message has a 1-second timeout.
Only run against an active meeting you have selected and are allowed to inspect.
--help does not access Accessibility.
"""

struct SystemAX: ProbeAX {
    func bundleID(pid: Int32) -> String? { NSRunningApplication(processIdentifier: pid)?.bundleIdentifier }
    func trusted() -> Bool { AXIsProcessTrusted() }
    func clock() -> UInt64 { mach_absolute_time() }
    func check(_ error: AXError) throws {
        guard error == .success else { throw ProbeFailure.ax(error.rawValue) }
    }
    func bounded(_ node: AXUIElement) throws -> AXUIElement {
        try check(AXUIElementSetMessagingTimeout(node, 1))
        return node
    }
    func focusedWindow(pid: Int32) throws -> AXUIElement {
        let app = try bounded(AXUIElementCreateApplication(pid))
        let value = try self.value(app, kAXFocusedWindowAttribute as String)
        guard CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() else { throw ProbeFailure.message("invalid focused window") }
        return try bounded(unsafeBitCast(value as CFTypeRef, to: AXUIElement.self))
    }
    func value(_ node: AXUIElement, _ attribute: String) throws -> Any {
        var result: CFTypeRef?
        try check(AXUIElementCopyAttributeValue(node, attribute as CFString, &result))
        guard let result else { throw ProbeFailure.message("empty attribute value") }
        return result
    }
    func attributes(_ node: AXUIElement) throws -> [String] {
        var names: CFArray?
        try check(AXUIElementCopyAttributeNames(node, &names))
        guard let result = names as? [String] else { throw ProbeFailure.message("invalid attribute names") }
        return result
    }
    func children(_ node: AXUIElement, start: Int, count: Int) throws -> [AXUIElement] {
        var total: CFIndex = 0
        try check(AXUIElementGetAttributeValueCount(node, kAXChildrenAttribute as CFString, &total))
        guard start < total else { return [] }
        var values: CFArray?
        try check(AXUIElementCopyAttributeValues(node, kAXChildrenAttribute as CFString, start, min(count, total - start), &values))
        guard let values = values as? [AXUIElement] else { throw ProbeFailure.message("invalid children") }
        return try values.map(bounded)
    }
}

#if !PROBE_TESTS
@main struct ProbeMain {
    static func main() {
        let output = probe(Array(CommandLine.arguments.dropFirst()), ax: SystemAX())
        print(output)
        if output.hasPrefix("refused:") || output.hasPrefix("AX error") { exit(1) }
    }
}
#endif
