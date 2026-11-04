import Cocoa

/// A tool that the menu and the window group their items by. The square colours are the pieces
/// of the app icon.
enum MysliTool: CaseIterable {
    case screenshots, clipboard, windows, keepAwake, meetings

    var title: String {
        switch self {
        case .screenshots: "Screenshots"
        case .clipboard: "Clipboard"
        case .windows: "Windows"
        case .keepAwake: "Keep Awake"
        case .meetings: "Meetings"
        }
    }

    var symbolName: String {
        switch self {
        case .screenshots: "camera.viewfinder"
        case .clipboard: "list.clipboard"
        case .windows: "rectangle.split.2x1"
        case .keepAwake: "cup.and.saucer.fill"
        case .meetings: "waveform"
        }
    }

    private var colors: (square: NSColor, symbol: NSColor) {
        switch self {
        case .screenshots: (Self.rgb(0xE2B07A), Self.roast)
        case .clipboard: (Self.rgb(0xE9CE96), Self.roast)
        case .windows: (Self.rgb(0xD9A441), Self.roast)
        case .keepAwake: (Self.rgb(0x5A3A24), .white)
        case .meetings: (Self.rgb(0xB4233C), .white)
        }
    }

    private static let roast = rgb(0x2E2118)

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// A rounded square in the tool's colour with its symbol on top.
    func icon(size: CGFloat) -> NSImage {
        let (square, symbol) = colors
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            square.setFill()
            NSBezierPath(roundedRect: rect, xRadius: size / 4, yRadius: size / 4).fill()
            let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.55, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [symbol]))
            guard let glyph = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) else { return true }
            glyph.draw(in: NSRect(x: rect.midX - glyph.size.width / 2, y: rect.midY - glyph.size.height / 2,
                                  width: glyph.size.width, height: glyph.size.height))
            return true
        }
        image.accessibilityDescription = title
        return image
    }
}
