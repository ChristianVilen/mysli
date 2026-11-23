#if DEBUG
import AppKit

@MainActor
enum AppKitPreview {
    static func host(_ view: NSView, size: NSSize? = nil, retaining owner: AnyObject? = nil) -> NSViewController {
        let size = size ?? view.frame.size
        return PreviewContentController(content: view, size: size, owner: owner)
    }

    static func host(contentOf window: NSWindow, retaining owner: AnyObject? = nil) -> NSViewController {
        let content = window.contentView ?? NSView(frame: window.contentLayoutRect)
        window.contentView = nil
        return host(content, retaining: owner ?? window)
    }

    static func defaults() -> UserDefaults {
        PreviewDefaults()
    }
}

private final class PreviewContentController: NSViewController {
    private let owner: AnyObject?

    init(content: NSView, size: NSSize, owner: AnyObject?) {
        self.owner = owner
        super.init(nibName: nil, bundle: nil)
        content.frame = NSRect(origin: .zero, size: size)
        view = content
        preferredContentSize = size
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

private final class PreviewDefaults: UserDefaults {
    private var values: [String: Any] = [:]

    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func array(forKey key: String) -> [Any]? { values[key] as? [Any] }
    override func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
    override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    override func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }

    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func set(_ value: Bool, forKey key: String) { values[key] = value }
    override func set(_ value: Int, forKey key: String) { values[key] = value }
    override func set(_ value: Double, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values[key] = nil }
}
#endif
