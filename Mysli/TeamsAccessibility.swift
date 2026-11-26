import Foundation
import AppKit
import ApplicationServices

struct TeamsAXMetadata: Equatable {
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
    TeamsWebContentSource(source: TeamsAccessibility(reader: NativeTeamsAX()), webContent: TeamsWebContentSwitch())
}

/// What one scan reads at most. A scan that goes over a limit gives no name.
enum TeamsScanLimit: String, Sendable {
    case windows, nodes, depth, children, text

    /// In a real call on 2026-11-25 the longest scan took 0.155 s.
    static let deadline: TimeInterval = 0.25

    var maximum: Int {
        switch self {
        case .windows: 8
        // The meeting window of a real call on 2026-11-25 grew past 512 nodes.
        case .nodes: 2048
        // The participant strip beside a shared screen reaches depth 27.
        case .depth: 32
        case .children: 40
        // UTF-8 bytes of one label.
        case .text: 256
        }
    }
}

/// How `NativeTeamsAX` reads the status, the counts, and the values that the AX API gives back.
enum TeamsAXRules {
    static let bundleIdentifier = "com.microsoft.teams2"

    /// False for an attribute that the element does not have; any other failure ends the scan.
    static func hasValue(_ status: AXError) throws -> Bool {
        switch status {
        case .success: return true
        case .attributeUnsupported, .noValue: return false
        default: throw TeamsScanReason.axError(status.rawValue)
        }
    }

    static func checkCount(_ count: Int, limit: TeamsScanLimit) throws {
        guard count >= 0 else { throw TeamsScanReason.unexpectedAXValue }
        guard count <= limit.maximum else { throw TeamsScanReason.scanLimit(limit) }
    }

    /// The attributes that `metadata(from:)` reads, in the order of its values.
    static let metadataAttributes = [kAXRoleAttribute, kAXIdentifierAttribute, "AXDOMClassList", kAXPositionAttribute,
                                     kAXSizeAttribute, kAXEnabledAttribute, "AXHidden"]

    /// `values` come from `AXUIElementCopyMultipleAttributeValues` for `metadataAttributes`. `visible` leaves out
    /// whether a window is minimized.
    static func metadata(from values: [CFTypeRef]) throws -> TeamsAXMetadata {
        guard values.count == metadataAttributes.count else { throw TeamsScanReason.unexpectedAXValue }
        var present: [String: CFTypeRef] = [:]
        for (attribute, raw) in zip(metadataAttributes, values) { present[attribute] = try value(raw) }
        guard let classes = TeamsAXMetadata.domClasses(present["AXDOMClassList"]) else {
            throw TeamsScanReason.unexpectedAXValue
        }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        if let position = present[kAXPositionAttribute] {
            guard CFGetTypeID(position) == AXValueGetTypeID(),
                  AXValueGetValue(position as! AXValue, .cgPoint, &point) else { throw TeamsScanReason.unexpectedAXValue }
        }
        if let size = present[kAXSizeAttribute] {
            guard CFGetTypeID(size) == AXValueGetTypeID(),
                  AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { throw TeamsScanReason.unexpectedAXValue }
        }
        return TeamsAXMetadata(role: try string(present[kAXRoleAttribute]) ?? "",
                               identifier: try string(present[kAXIdentifierAttribute]) ?? "",
                               classes: classes, bounds: CGRect(origin: point, size: dimensions),
                               enabled: try boolean(present[kAXEnabledAttribute]) ?? false,
                               visible: !(try boolean(present["AXHidden"]) ?? false))
    }

    /// The multiple-value call gives CFNull or an error value in place of an attribute without a value.
    private static func value(_ raw: CFTypeRef) throws -> CFTypeRef? {
        if CFGetTypeID(raw) == CFNullGetTypeID() { return nil }
        guard CFGetTypeID(raw) == AXValueGetTypeID(), AXValueGetType(raw as! AXValue) == .axError else { return raw }
        var error = AXError.success
        guard AXValueGetValue(raw as! AXValue, .axError, &error), try !hasValue(error) else {
            throw TeamsScanReason.unexpectedAXValue
        }
        return nil
    }

    static func string(_ raw: CFTypeRef?) throws -> String? {
        guard let raw else { return nil }
        guard let text = raw as? String else { throw TeamsScanReason.unexpectedAXValue }
        return text
    }

    static func boolean(_ raw: CFTypeRef?) throws -> Bool? {
        guard let raw else { return nil }
        guard CFGetTypeID(raw) == CFBooleanGetTypeID() else { throw TeamsScanReason.unexpectedAXValue }
        return (raw as! CFBoolean) == kCFBooleanTrue
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
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: TeamsAXRules.bundleIdentifier)
        guard !apps.isEmpty else { throw TeamsScanReason.noTeamsApp }
        var result: [Node] = []
        for app in apps {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            result += try elements(root, attribute: kAXWindowsAttribute, limit: .windows, deadline: deadline)
            if result.count > TeamsScanLimit.windows.maximum { break }
        }
        return result
    }

    func metadata(_ node: Node, timeout: TimeInterval) throws -> TeamsAXMetadata {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        try prepare(node.element, deadline: deadline)
        var raw: CFArray?
        let status = AXUIElementCopyMultipleAttributeValues(node.element, TeamsAXRules.metadataAttributes as CFArray,
                                                            AXCopyMultipleAttributeOptions(), &raw)
        guard status == .success else { throw TeamsScanReason.axError(status.rawValue) }
        guard let raw else { throw TeamsScanReason.unexpectedAXValue }
        var metadata = try TeamsAXRules.metadata(from: raw as [AnyObject])
        if metadata.role == kAXWindowRole, try boolean(node.element, kAXMinimizedAttribute, deadline: deadline) == true {
            metadata.visible = false
        }
        return metadata
    }

    func children(_ node: Node, timeout: TimeInterval) throws -> [Node] {
        try elements(node.element, attribute: kAXChildrenAttribute, limit: .children,
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
        try TeamsAXRules.string(value(element, attribute, deadline: deadline))
    }

    private func boolean(_ element: AXUIElement, _ attribute: String, deadline: TimeInterval) throws -> Bool? {
        try TeamsAXRules.boolean(value(element, attribute, deadline: deadline))
    }

    private func elements(_ element: AXUIElement, attribute: String, limit: TeamsScanLimit,
                          deadline: TimeInterval) throws -> [Node] {
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

/// Window wrappers and call controls were observed in a real Teams call. On 2026-11-16, beside a shared
/// screen, a participant `AXMenuItem` had a `vdi-frame-occlusion` child with two `borders` classes while
/// that person spoke. The gallery tile structure remains unverified. Fake trees test policy only.
final class TeamsAccessibility<Reader: TeamsAXReading> {
    private struct Item {
        let node: Reader.Node
        let parent: Int?
        let metadata: TeamsAXMetadata
        var subtree: Range<Int>
        let rootOwned: Bool
        let selfOwned: Bool
        let bounded: Bool
        let tileMember: Bool
    }
    private struct MeetingControls {
        let node: Reader.Node
        let parent: Int?
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
        var nodes: Set<Reader.Node> = []
        var tiles: Set<Int> = []
        var controls: [MeetingControls] = []

        /// Nil for a tile without the supported structure.
        func participant(_ index: Int) -> (tile: Reader.Node, name: Reader.Node)? {
            let tile = items[index]
            guard ["AXGroup", "AXMenuItem"].contains(tile.metadata.role), tile.rootOwned else { return nil }
            let isMenuItem = tile.metadata.role == "AXMenuItem"
            // A menu item becomes a tile only through a marker child, which the walk never reaches in a
            // forbidden or hidden item, so only the item's descendants need the member check.
            let members = isMenuItem ? items[tile.subtree].dropFirst() : items[tile.subtree]
            guard members.allSatisfy(\.tileMember) else { return nil }
            let names = members.filter { $0.metadata.role == "AXStaticText" }
            guard names.count == 1, let name = names.first, name.metadata.visible else { return nil }
            // Teams draws the name chip of a participant item above a 3 px bar that is its parent, so only
            // the item itself can contain the name.
            let owned = isMenuItem
                ? TeamsAccessibility.validBounds(name.metadata.bounds) && tile.metadata.bounds.contains(name.metadata.bounds)
                : name.bounded
            return owned ? (tile.node, name.node) : nil
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
        let deadline = now() + TeamsScanLimit.deadline
        var count = 0
        do {
            let windows = try reader.windows(timeout: budget(deadline))
            guard windows.count <= TeamsScanLimit.windows.maximum else { throw TeamsScanReason.scanLimit(.windows) }
            contexts = contexts.filter { windows.contains($0.key) }
            var meetings: [(Tree, Reader.Node)] = []
            for window in windows {
                var tree = Tree()
                try walk(window, parent: nil, ownership: Ownership(), depth: 0,
                         tree: &tree, count: &count, deadline: deadline)
                if try isMeeting(tree, deadline: deadline) { meetings.append((tree, window)) }
            }
            guard meetings.count <= 1 else { throw TeamsScanReason.multipleMeetingWindows }
            guard let (tree, window) = meetings.first else { throw TeamsScanReason.noMeetingWindow }
            if contexts[window] == nil { contexts[window] = UUID().uuidString }
            let speaker = try highlightedSpeaker(in: tree, deadline: deadline)
            _ = try budget(deadline)
            guard reader.isTrusted() else { throw TeamsScanReason.notTrusted }
            return TeamsAXSnapshot(sourceID: contexts[window], result: .named(speaker), nodes: count)
        } catch {
            let reason = error as? TeamsScanReason ?? .unexpectedAXValue
            if reason == .noTeamsApp { contexts = [:] }
            return TeamsAXSnapshot(result: .unnamed(reason), nodes: count)
        }
    }

    /// The user's own tiles drop out, so the user's own speaking border beside a remote one leaves the remote name.
    private func highlightedSpeaker(in tree: Tree, deadline: TimeInterval) throws -> TeamsSpeakerName {
        guard !tree.tiles.isEmpty else { throw TeamsScanReason.noHighlightedTile }
        let results = Set(try tree.tiles.sorted().compactMap { try tileResult($0, in: tree, deadline: deadline) })
        guard results.count <= 1 else { throw TeamsScanReason.multipleHighlightedTiles }
        switch results.first {
        case .named(let speaker): return speaker
        case .unnamed(let reason): throw reason
        case nil: throw TeamsScanReason.selfTile
        }
    }

    /// Nil for the user's own tile. A tile that fails a check before it shows whose it is counts as someone else's.
    private func tileResult(_ index: Int, in tree: Tree, deadline: TimeInterval) throws -> TeamsScanResult? {
        guard !tree.items[index].selfOwned else { return nil }
        guard let participant = tree.participant(index) else { return .unnamed(.unsupportedTile) }
        let tileLabel = try readLabel(participant.tile, kind: .tile, deadline: deadline)
        guard tileLabel?.lowercased().hasPrefix("myself video") != true else { return nil }
        guard let text = try reader.label(participant.name, kind: .name, timeout: budget(deadline)),
              text.utf8.count <= TeamsScanLimit.text.maximum, let speaker = TeamsSpeakerName(text) else {
            return .unnamed(.nameRejected)
        }
        guard speaker.value.lowercased() != "you", !speaker.value.lowercased().hasSuffix("(you)") else { return nil }
        return .named(speaker)
    }

    private static func validBounds(_ bounds: CGRect) -> Bool {
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
        guard depth <= TeamsScanLimit.depth.maximum else { throw TeamsScanReason.scanLimit(.depth) }
        guard count < TeamsScanLimit.nodes.maximum else { throw TeamsScanReason.scanLimit(.nodes) }
        guard tree.nodes.insert(node).inserted else { throw TeamsScanReason.unexpectedAXValue }
        count += 1
        let metadata = try reader.metadata(node, timeout: budget(deadline))
        let index = tree.items.count
        let excluded = forbidden(metadata)
        let selfScope = ownership.selfScope || isSelf(metadata)
        let bounded = Self.validBounds(metadata.bounds) && ownership.bounds.contains(metadata.bounds)
        tree.items.append(Item(node: node, parent: parent, metadata: metadata, subtree: index..<(index + 1),
                               rootOwned: ownership.rootScope && bounded, selfOwned: selfScope,
                               bounded: bounded,
                               tileMember: !excluded && !isSelf(metadata)
                                   && ["AXGroup", "AXStaticText", "AXImage", "AXButton"].contains(metadata.role)))
        if metadata.visible, metadata.classes.intersection(Self.borders).count >= 2 {
            if metadata.classes.contains("vdi-frame-occlusion") {
                if let parent, bounded, tree.items[parent].metadata.role == "AXMenuItem" { tree.tiles.insert(parent) }
                else { tree.tiles.insert(index) }
            } else if let parent, tree.items[parent].metadata.classes.contains("vdi-frame-occlusion"),
                    tree.items[parent].metadata.bounds == metadata.bounds { tree.tiles.insert(parent) }
        }
        guard !excluded, metadata.visible else { return }
        var control: Int?
        if metadata.role == "AXToolbar", metadata.enabled, ownership.rootScope, bounded,
           tree.items.first?.metadata.role == "AXWindow" {
            control = tree.controls.count
            tree.controls.append(MeetingControls(node: node, parent: parent, identifier: metadata.identifier.lowercased()))
        } else if metadata.role == "AXGroup" {
            control = ownership.control
        }
        if metadata.role == "AXButton", metadata.enabled, Self.validBounds(metadata.bounds),
           let owner = ownership.control {
            tree.controls[owner].buttons.append(node)
        }
        let descendants = Ownership(
            bounds: Self.validBounds(metadata.bounds) ? ownership.bounds.intersection(metadata.bounds) : .null,
            rootScope: ownership.rootScope && ["AXWindow", "AXWebArea", "AXScrollArea", "AXGroup"].contains(metadata.role),
            selfScope: selfScope,
            control: control)
        let children = try reader.children(node, timeout: budget(deadline))
        guard children.count <= TeamsScanLimit.children.maximum else { throw TeamsScanReason.scanLimit(.children) }
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

    private func isMeeting(_ tree: Tree, deadline: TimeInterval) throws -> Bool {
        for control in tree.controls {
            let knownScope: Bool
            if ["meeting-controls", "calling-controls"].contains(control.identifier) { knownScope = true }
            else {
                let label = try readLabel(control.node, kind: .control, deadline: deadline)
                knownScope = label == "Meeting controls" || label == "Calling controls"
            }
            guard knownScope else { continue }
            if try hasEndCallButton(control.buttons, deadline: deadline) { return true }
            for (index, group) in tree.items.enumerated() {
                let metadata = group.metadata
                guard group.parent == control.parent, metadata.role == "AXGroup",
                      group.rootOwned, metadata.visible, !group.selfOwned, !forbidden(metadata) else { continue }
                let buttons = tree.items.filter {
                    $0.parent == index && $0.metadata.role == "AXButton"
                        && $0.metadata.enabled && $0.metadata.visible && $0.bounded && !forbidden($0.metadata)
                }.map(\.node)
                guard !buttons.isEmpty else { continue }
                let callingControls: Bool
                if metadata.identifier.lowercased() == "calling-controls" { callingControls = true }
                else {
                    callingControls = try readLabel(group.node, kind: .control, deadline: deadline) == "Calling controls"
                }
                if callingControls, try hasEndCallButton(buttons, deadline: deadline) { return true }
            }
        }
        return false
    }

    private func hasEndCallButton(_ buttons: [Reader.Node], deadline: TimeInterval) throws -> Bool {
        for button in buttons {
            let label = try readLabel(button, kind: .control, deadline: deadline)
            if label == "Hang up" || label == "Leave" { return true }
        }
        return false
    }

    private func readLabel(_ node: Reader.Node, kind: TeamsAXLabel, deadline: TimeInterval) throws -> String? {
        let label = try reader.label(node, kind: kind, timeout: budget(deadline))
        guard label?.utf8.count ?? 0 <= TeamsScanLimit.text.maximum else { throw TeamsScanReason.scanLimit(.text) }
        return label
    }
}
