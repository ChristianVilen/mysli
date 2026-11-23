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
}

final class PreviewDefaults {
    let suite = "Mysli.Preview." + UUID().uuidString
    let values: UserDefaults

    init() {
        values = UserDefaults(suiteName: suite)!
    }

    deinit { values.removePersistentDomain(forName: suite) }
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

struct PreviewScreens: Screens {
    var all: [ScreenGeometry] = []
    var mainIndex: Int? { all.isEmpty ? nil : 0 }
}

#endif
