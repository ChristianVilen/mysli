import Foundation
import AppKit
import ApplicationServices

struct TeamsAXMetadata {
    var role = "AXGroup"
    var identifier = ""
    var classes: Set<String> = []
    var bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
    var enabled = true
    var visible = true

    static func domClasses(_ raw: Any?) -> Set<String>? {
        guard let raw else { return [] }
        if let list = raw as? [String] { return Set(list) }
        if let text = raw as? String { return Set(text.split(whereSeparator: \.isWhitespace).map(String.init)) }
        return nil
    }
}

func makeNativeTeamsSnapshotSource() -> any TeamsSnapshotReading {
    TeamsAccessibility(reader: NativeTeamsAX())
}

/// How `NativeTeamsAX` reads the status and the counts that the AX API gives back.
enum TeamsAXRules {
    /// False for an attribute that the element does not have; any other failure ends the scan.
    static func hasValue(_ status: AXError) throws -> Bool {
        switch status {
        case .success: return true
        case .attributeUnsupported, .noValue: return false
        default: throw TeamsScanReason.axError(status.rawValue)
        }
    }

    static func checkCount(_ count: Int, limit: Int) throws {
        guard count >= 0 else { throw TeamsScanReason.unexpectedAXValue }
        guard count <= limit else { throw TeamsScanReason.scanLimit }
    }
}

private final class NativeTeamsAX: TeamsAXReading {
    struct Node: Hashable {
        let element: AXUIElement
        static func == (lhs: Node, rhs: Node) -> Bool { CFEqual(lhs.element, rhs.element) }
        func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
    }

    func isTrusted() -> Bool { AXIsProcessTrusted() }

    func windows(timeout: TimeInterval) throws -> [Node] {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.teams2")
        guard !apps.isEmpty else { throw TeamsScanReason.noTeamsApp }
        var result: [Node] = []
        for app in apps {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            result += try elements(root, attribute: kAXWindowsAttribute, limit: 8, deadline: deadline)
            if result.count > 8 { break }
        }
        return result
    }

    func metadata(_ node: Node, timeout: TimeInterval) throws -> TeamsAXMetadata {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let role = try string(node.element, kAXRoleAttribute, deadline: deadline) ?? ""
        let identifier = try string(node.element, kAXIdentifierAttribute, deadline: deadline) ?? ""
        let rawClasses = try value(node.element, "AXDOMClassList", deadline: deadline)
        guard let classes = TeamsAXMetadata.domClasses(rawClasses) else { throw TeamsScanReason.unexpectedAXValue }
        let position = try value(node.element, kAXPositionAttribute, deadline: deadline)
        let size = try value(node.element, kAXSizeAttribute, deadline: deadline)
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        if let position {
            guard CFGetTypeID(position) == AXValueGetTypeID(),
                  AXValueGetValue(position as! AXValue, .cgPoint, &point) else { throw TeamsScanReason.unexpectedAXValue }
        }
        if let size {
            guard CFGetTypeID(size) == AXValueGetTypeID(),
                  AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { throw TeamsScanReason.unexpectedAXValue }
        }
        let enabled = try boolean(node.element, kAXEnabledAttribute, deadline: deadline) ?? false
        let hidden = try boolean(node.element, "AXHidden", deadline: deadline) ?? false
        let minimized = role == kAXWindowRole ? try boolean(node.element, kAXMinimizedAttribute, deadline: deadline) ?? false : false
        return TeamsAXMetadata(role: role, identifier: identifier, classes: classes,
                               bounds: CGRect(origin: point, size: dimensions), enabled: enabled,
                               visible: !hidden && !minimized)
    }

    func children(_ node: Node, timeout: TimeInterval) throws -> [Node] {
        try elements(node.element, attribute: kAXChildrenAttribute, limit: 40,
                     deadline: ProcessInfo.processInfo.systemUptime + timeout)
    }

    func label(_ node: Node, kind: TeamsAXLabel, timeout: TimeInterval) throws -> String? {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let attributes: [String]
        switch kind {
        case .name: attributes = [kAXValueAttribute, kAXTitleAttribute]
        case .control: attributes = [kAXTitleAttribute, kAXDescriptionAttribute]
        case .tile: attributes = [kAXDescriptionAttribute]
        }
        for attribute in attributes {
            if let text = try string(node.element, attribute, deadline: deadline), !text.isEmpty {
                return text
            }
        }
        return nil
    }

    private func prepare(_ element: AXUIElement, deadline: TimeInterval) throws {
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard !Task.isCancelled, remaining > 0 else { throw TeamsScanReason.deadline }
        let status = AXUIElementSetMessagingTimeout(element, Float(min(0.05, remaining)).nextDown)
        guard status == .success else { throw TeamsScanReason.axError(status.rawValue) }
    }

    private func value(_ element: AXUIElement, _ attribute: String, deadline: TimeInterval) throws -> CFTypeRef? {
        try prepare(element, deadline: deadline)
        var result: CFTypeRef?
        guard try TeamsAXRules.hasValue(AXUIElementCopyAttributeValue(element, attribute as CFString, &result)) else {
            return nil
        }
        return result
    }

    private func string(_ element: AXUIElement, _ attribute: String, deadline: TimeInterval) throws -> String? {
        guard let raw = try value(element, attribute, deadline: deadline) else { return nil }
        guard let text = raw as? String else { throw TeamsScanReason.unexpectedAXValue }
        return text
    }

    private func boolean(_ element: AXUIElement, _ attribute: String, deadline: TimeInterval) throws -> Bool? {
        guard let raw = try value(element, attribute, deadline: deadline) else { return nil }
        guard CFGetTypeID(raw) == CFBooleanGetTypeID() else { throw TeamsScanReason.unexpectedAXValue }
        return (raw as! CFBoolean) == kCFBooleanTrue
    }

    private func elements(_ element: AXUIElement, attribute: String, limit: Int, deadline: TimeInterval) throws -> [Node] {
        try prepare(element, deadline: deadline)
        var count: CFIndex = 0
        guard try TeamsAXRules.hasValue(AXUIElementGetAttributeValueCount(element, attribute as CFString, &count)) else {
            return []
        }
        try TeamsAXRules.checkCount(count, limit: limit)
        guard count > 0 else { return [] }
        try prepare(element, deadline: deadline)
        var raw: CFArray?
        guard try TeamsAXRules.hasValue(AXUIElementCopyAttributeValues(element, attribute as CFString, 0, count, &raw)),
              let raw else { return [] }
        return try (raw as [AnyObject]).map { item in
            guard CFGetTypeID(item) == AXUIElementGetTypeID() else { throw TeamsScanReason.unexpectedAXValue }
            return Node(element: item as! AXUIElement)
        }
    }
}

enum TeamsAXLabel { case control, tile, name }

protocol TeamsAXReading {
    associatedtype Node: Hashable
    func isTrusted() -> Bool
    func windows(timeout: TimeInterval) throws -> [Node]
    func metadata(_ node: Node, timeout: TimeInterval) throws -> TeamsAXMetadata
    func children(_ node: Node, timeout: TimeInterval) throws -> [Node]
    func label(_ node: Node, kind: TeamsAXLabel, timeout: TimeInterval) throws -> String?
}

struct TeamsAXSnapshot: Equatable, Sendable {
    var sourceID: String?
    var result: TeamsScanResult
    /// The AX nodes whose metadata the scan read.
    var nodes = 0
}

final class TeamsAccessibility<Reader: TeamsAXReading> {
    private struct Item {
        let node: Reader.Node
        let metadata: TeamsAXMetadata
        var subtree: Range<Int>
        let rootOwned: Bool
        let selfOwned: Bool
        let bounded: Bool
        let tileMember: Bool
    }
    private struct MeetingControls {
        let node: Reader.Node
        let identifier: String
        var buttons: [Reader.Node] = []
    }
    private struct Ownership {
        var bounds = CGRect.infinite
        var rootScope = true
        var selfScope = false
        var control: Int?
    }
    private struct Tree {
        var items: [Item] = []
        var tiles: Set<Int> = []
        var controls: [MeetingControls] = []

        func participant() throws -> (tile: Reader.Node, name: Reader.Node) {
            guard let index = tiles.first else { throw TeamsScanReason.noHighlightedTile }
            guard tiles.count == 1 else { throw TeamsScanReason.multipleHighlightedTiles }
            let tile = items[index]
            guard !tile.selfOwned else { throw TeamsScanReason.selfTile }
            guard tile.metadata.role == "AXGroup", tile.rootOwned else { throw TeamsScanReason.unsupportedTile }
            let members = items[tile.subtree]
            guard members.allSatisfy(\.tileMember) else { throw TeamsScanReason.unsupportedTile }
            let names = members.filter { $0.metadata.role == "AXStaticText" }
            guard names.count == 1, let name = names.first,
                  name.metadata.visible, name.bounded else { throw TeamsScanReason.unsupportedTile }
            return (tile.node, name.node)
        }
    }
    private static var borders: Set<String> { ["frwhdur", "f578s74", "f4mjgsl", "f1xul6tz", "fj20gam", "f3ve9t9"] }
    private var contexts: [Reader.Node: String] = [:]
    let reader: Reader
    let now: () -> TimeInterval
    init(reader: Reader, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.reader = reader
        self.now = now
    }
    func snapshot() -> TeamsAXSnapshot {
        guard reader.isTrusted() else { return TeamsAXSnapshot(result: .unnamed(.notTrusted)) }
        let deadline = now() + 0.15
        var count = 0
        do {
            let windows = try reader.windows(timeout: budget(deadline))
            guard windows.count <= 8 else { throw TeamsScanReason.scanLimit }
            contexts = contexts.filter { windows.contains($0.key) }
            var meetings: [(Tree, Reader.Node)] = []
            for window in windows {
                var tree = Tree()
                try walk(window, parent: nil, ownership: Ownership(), depth: 0,
                         tree: &tree, count: &count, deadline: deadline)
                if try isMeeting(tree.controls, deadline: deadline) { meetings.append((tree, window)) }
            }
            guard meetings.count <= 1 else { throw TeamsScanReason.multipleMeetingWindows }
            guard let (tree, window) = meetings.first else { throw TeamsScanReason.noMeetingWindow }
            if contexts[window] == nil { contexts[window] = UUID().uuidString }
            let participant = try tree.participant()
            let tileLabel = try reader.label(participant.tile, kind: .tile, timeout: budget(deadline))
            guard tileLabel?.utf8.count ?? 0 <= 256 else { throw TeamsScanReason.scanLimit }
            guard tileLabel?.lowercased().hasPrefix("myself video") != true else { throw TeamsScanReason.selfTile }
            guard let text = try reader.label(participant.name, kind: .name, timeout: budget(deadline)),
                  text.utf8.count <= 256, let speaker = TeamsSpeakerName(text) else {
                throw TeamsScanReason.nameRejected
            }
            guard speaker.value.lowercased() != "you", !speaker.value.lowercased().hasSuffix("(you)") else {
                throw TeamsScanReason.selfTile
            }
            _ = try budget(deadline)
            guard reader.isTrusted() else { throw TeamsScanReason.notTrusted }
            return TeamsAXSnapshot(sourceID: contexts[window], result: .named(speaker), nodes: count)
        } catch {
            let reason = error as? TeamsScanReason ?? .unexpectedAXValue
            if reason == .noTeamsApp { contexts = [:] }
            return TeamsAXSnapshot(result: .unnamed(reason), nodes: count)
        }
    }

    private func validBounds(_ bounds: CGRect) -> Bool {
        [bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height].allSatisfy(\.isFinite)
            && bounds.size.width > 0 && bounds.size.height > 0
    }

    private func budget(_ deadline: TimeInterval) throws -> TimeInterval {
        let remaining = deadline - now()
        guard !Task.isCancelled, remaining > 0 else { throw TeamsScanReason.deadline }
        return min(0.05, remaining)
    }

    private func walk(_ node: Reader.Node, parent: Int?, ownership: Ownership, depth: Int, tree: inout Tree, count: inout Int,
                      deadline: TimeInterval) throws {
        guard depth <= 16, count < 512 else { throw TeamsScanReason.scanLimit }
        guard !tree.items.contains(where: { $0.node == node }) else { throw TeamsScanReason.unexpectedAXValue }
        count += 1
        let metadata = try reader.metadata(node, timeout: budget(deadline))
        let index = tree.items.count
        let excluded = forbidden(metadata)
        let selfScope = ownership.selfScope || isSelf(metadata)
        let bounded = validBounds(metadata.bounds) && ownership.bounds.contains(metadata.bounds)
        tree.items.append(Item(node: node, metadata: metadata, subtree: index..<(index + 1),
                               rootOwned: ownership.rootScope && bounded, selfOwned: selfScope,
                               bounded: bounded,
                               tileMember: !excluded && !isSelf(metadata)
                                   && ["AXGroup", "AXStaticText", "AXImage", "AXButton"].contains(metadata.role)))
        if metadata.visible, metadata.classes.intersection(Self.borders).count >= 2 {
            if metadata.classes.contains("vdi-frame-occlusion") { tree.tiles.insert(index) }
            else if let parent, tree.items[parent].metadata.classes.contains("vdi-frame-occlusion"),
                    tree.items[parent].metadata.bounds == metadata.bounds { tree.tiles.insert(parent) }
        }
        guard !excluded, metadata.visible else { return }
        var control: Int?
        if metadata.role == "AXToolbar", metadata.enabled, ownership.rootScope, bounded,
           tree.items.first?.metadata.role == "AXWindow" {
            control = tree.controls.count
            tree.controls.append(MeetingControls(node: node, identifier: metadata.identifier.lowercased()))
        } else if metadata.role == "AXGroup" {
            control = ownership.control
        }
        if metadata.role == "AXButton", metadata.enabled, validBounds(metadata.bounds),
           let owner = ownership.control {
            tree.controls[owner].buttons.append(node)
        }
        let descendants = Ownership(
            bounds: validBounds(metadata.bounds) ? ownership.bounds.intersection(metadata.bounds) : .null,
            rootScope: ownership.rootScope && ["AXWindow", "AXWebArea", "AXGroup"].contains(metadata.role),
            selfScope: selfScope,
            control: control)
        let children = try reader.children(node, timeout: budget(deadline))
        guard children.count <= 40 else { throw TeamsScanReason.scanLimit }
        for child in children {
            try walk(child, parent: index, ownership: descendants, depth: depth + 1,
                     tree: &tree, count: &count, deadline: deadline)
        }
        tree.items[index].subtree = index..<tree.items.count
    }

    private func forbidden(_ metadata: TeamsAXMetadata) -> Bool {
        let scope = (metadata.identifier + " " + metadata.classes.sorted().joined(separator: " ")).lowercased()
        return ["AXTextField", "AXSecureTextField", "AXTextArea", "AXDocument"].contains(metadata.role)
            || ["chat", "caption", "shared", "sharing", "document", "roster", "participant-list"].contains(where: { scope.contains($0) })
    }

    private func isSelf(_ metadata: TeamsAXMetadata) -> Bool {
        (metadata.identifier + " " + metadata.classes.joined(separator: " ")).lowercased().contains("self")
    }

    private func isMeeting(_ controls: [MeetingControls], deadline: TimeInterval) throws -> Bool {
        for control in controls {
            let knownScope: Bool
            if ["meeting-controls", "calling-controls"].contains(control.identifier) { knownScope = true }
            else {
                let label = try reader.label(control.node, kind: .control, timeout: budget(deadline))
                guard label?.utf8.count ?? 0 <= 256 else { throw TeamsScanReason.scanLimit }
                knownScope = label == "Meeting controls" || label == "Calling controls"
            }
            guard knownScope else { continue }
            for button in control.buttons {
                let label = try reader.label(button, kind: .control, timeout: budget(deadline))
                guard label?.utf8.count ?? 0 <= 256 else { throw TeamsScanReason.scanLimit }
                if label == "Hang up" || label == "Leave" { return true }
            }
        }
        return false
    }
}
