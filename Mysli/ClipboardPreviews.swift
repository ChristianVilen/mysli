#if DEBUG
import Cocoa
import SwiftUI

#Preview("Clipboard history") {
    ClipboardPreview.panel(items: ClipboardPreview.items())
}

#Preview("Clipboard history · empty") {
    ClipboardPreview.panel(items: [])
}

#Preview("Clipboard history · paste formatting") {
    ClipboardPreview.panel(items: ClipboardPreview.items(), showFormattingChooser: true)
}

@MainActor
private enum ClipboardPreview {
    static func panel(items: [ClipboardItem], showFormattingChooser: Bool = false) -> NSViewController {
        let clipboard = PreviewClipboardIO()
        let controller = ClipboardHistoryController(reader: clipboard, writer: clipboard,
                                                    keystrokes: clipboard, delay: { $0() })
        controller.seedPreviewItems(items)
        if showFormattingChooser { controller.enterPressed() }

        let panel = ClipboardPanel(controller: controller, screens: CapturePreviewScreens())
        controller.onListChanged = { [weak panel] in panel?.reload() }
        panel.reload()
        return AppKitPreview.host(contentOf: panel)
    }

    static func items() -> [ClipboardItem] {
        let date = Date(timeIntervalSince1970: 0)
        let image = CapturePreview.sampleImage()
        let richText = ClipboardItem.text(plain: "Weekly overview", html: Data("<strong>Weekly overview</strong>".utf8),
                                          copiedAt: date)
        var items = [richText]
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                items.append(.image(png: png, pixelSize: CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh),
                                    copiedAt: date))
            }
        }
        items.append(.text(plain: "Send the revised agenda on Thursday.", copiedAt: date))
        items.append(.text(plain: "https://example.com/agenda", copiedAt: date))
        return items
    }
}

private final class PreviewClipboardIO: PasteboardReading, PasteboardWriting, KeystrokeSending {
    var changeCount: Int { 0 }
    func readCurrentItem(now: Date) -> ClipboardItem? { nil }
    func write(_ item: ClipboardItem, withFormatting: Bool) -> Int { changeCount }
    func sendPasteKeystroke() throws {}
}
#endif
