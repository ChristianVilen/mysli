#if DEBUG
import Cocoa
import SwiftUI

#Preview("Edit screenshot · annotated") {
    let editor = EditorWindow(image: CapturePreview.sampleImage(), fileURL: PreviewImageStore.fileURL,
                              store: PreviewImageStore(), screens: CapturePreviewScreens())
    editor.addPreviewStroke(NSBezierPath(ovalIn: NSRect(x: 305, y: 79, width: 149, height: 82)))
    return AppKitPreview.host(contentOf: editor)
}

#Preview("Crop screenshot") {
    let drawing = DrawingView(image: CapturePreview.sampleImage())
    drawing.frame = CapturePreview.frame
    let crop = CropOverlayView(frame: drawing.bounds, imagePixelSize: drawing.imagePixelSize)
    crop.cropRect = NSRect(x: 88, y: 56, width: 340, height: 184)
    crop.isEditing = true
    drawing.addSubview(crop)
    return AppKitPreview.host(drawing)
}

#Preview("Select screenshot region") {
    let desktop = CapturePreview.desktop()
    let selection = SelectionView(frame: desktop.bounds)
    selection.wantsLayer = true
    selection.showPreviewSelection(NSRect(x: 146, y: 66, width: 310, height: 165))
    desktop.addSubview(selection)
    return AppKitPreview.host(desktop)
}

#Preview("Screenshot thumbnail", traits: .fixedLayout(width: 200, height: 124)) {
    let image = CapturePreview.sampleImage()
    let frame = NSRect(origin: .zero, size: ThumbnailPanel.thumbSize(for: image))
    return AppKitPreview.host(contentOf: ThumbnailPanel(image: image, frame: frame))
}

#Preview("Combine screenshots", traits: .fixedLayout(width: 120, height: 40)) {
    let frame = NSRect(x: 0, y: 0, width: CombineButton.buttonWidth, height: CombineButton.buttonHeight)
    return AppKitPreview.host(contentOf: CombineButton(frame: frame))
}

#Preview("Screenshot flash") {
    let desktop = CapturePreview.desktop()
    desktop.addSubview(FlashView.previewOverlay(frame: desktop.bounds))
    return AppKitPreview.host(desktop)
}

@MainActor
enum CapturePreview {
    static let frame = NSRect(x: 0, y: 0, width: 520, height: 320)

    static func desktop() -> NSView {
        let view = NSView(frame: frame)
        let image = NSImageView(frame: view.bounds)
        image.image = sampleImage()
        view.addSubview(image)
        return view
    }

    static func sampleImage() -> NSImage {
        NSImage(size: frame.size, flipped: false) { rect in
            NSGradient(starting: NSColor(srgbRed: 0.10, green: 0.36, blue: 0.43, alpha: 1),
                       ending: NSColor(srgbRed: 0.64, green: 0.75, blue: 0.80, alpha: 1))?
                .draw(in: rect, angle: 35)

            NSColor(srgbRed: 0.96, green: 0.97, blue: 0.98, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 48, y: 38, width: 424, height: 244),
                         xRadius: 12, yRadius: 12).fill()

            for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: 64 + CGFloat(index) * 14, y: 263, width: 8, height: 8)).fill()
            }

            NSColor(srgbRed: 0.86, green: 0.91, blue: 0.93, alpha: 1).setFill()
            NSRect(x: 60, y: 50, width: 78, height: 196).fill()
            let sidebarItems = ["Overview", "Orders", "Stock"]
            for (index, title) in sidebarItems.enumerated() {
                label(title, at: NSPoint(x: 69, y: 223 - CGFloat(index) * 24), size: 11, weight: .medium)
            }

            label("Weekly overview", at: NSPoint(x: 158, y: 211), size: 23, weight: .semibold)
            label("Monday to Sunday", at: NSPoint(x: 159, y: 187), size: 12, weight: .regular)
            for (index, card) in [("Orders", "248"), ("Returns", "12")].enumerated() {
                let x = 156 + CGFloat(index) * 156
                NSColor.white.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: 78, width: 140, height: 84),
                             xRadius: 8, yRadius: 8).fill()
                label(card.0, at: NSPoint(x: x + 14, y: 133), size: 12, weight: .medium)
                label(card.1, at: NSPoint(x: x + 14, y: 93), size: 26, weight: .semibold)
            }
            return true
        }
    }

    private static func label(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight) {
        (text as NSString).draw(at: point, withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor(srgbRed: 0.14, green: 0.20, blue: 0.24, alpha: 1),
        ])
    }
}

struct CapturePreviewScreens: Screens {
    let all: [ScreenGeometry] = []
    let mainIndex: Int? = nil
}

private struct PreviewImageStore: ImageStoring {
    static let fileURL = URL(fileURLWithPath: "/Preview/Screenshot.png")

    func store(cgImage: CGImage) -> CaptureResult {
        CaptureResult(image: NSImage(cgImage: cgImage, size: .zero), fileURL: Self.fileURL)
    }

    func storeCombined(top: NSImage, bottom: NSImage) -> CaptureResult? { nil }
    func saveAnnotated(image: NSImage, to url: URL) {}
    func delete(at url: URL) {}
}
#endif
