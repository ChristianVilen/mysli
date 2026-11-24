import AppKit
import XCTest

/// Stands in for the desktop behind a floating panel in a picture.
let pictureDesktop = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        ? NSColor(red: 0.11, green: 0.16, blue: 0.16, alpha: 1)
        : NSColor(red: 0.79, green: 0.83, blue: 0.77, alpha: 1)
}

/// Draws each view at its origin over `backdrop` and writes one PNG at 2x. Off screen, glass and
/// visual effect views draw nothing, so the backdrop is what shows behind their content.
@MainActor
func writePicture(of parts: [(view: NSView, origin: NSPoint)], size: NSSize,
                  backdrop: NSColor = .windowBackgroundColor,
                  appearance name: NSAppearance.Name, to url: URL) throws {
    let appearance = try XCTUnwrap(NSAppearance(named: name))
    let scale: CGFloat = 2
    let context = try XCTUnwrap(CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                          bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    appearance.performAsCurrentDrawingAppearance {
        context.setFillColor(backdrop.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
    }
    for (view, origin) in parts {
        view.appearance = appearance
        view.layoutSubtreeIfNeeded()
        view.needsDisplay = true
        view.displayIfNeeded()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * scale), pixelsHigh: Int(view.bounds.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = view.bounds.size
        appearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: bitmap) }
        context.draw(try XCTUnwrap(bitmap.cgImage),
                     in: CGRect(x: origin.x * scale, y: origin.y * scale,
                                width: view.bounds.width * scale, height: view.bounds.height * scale))
    }
    let image = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
    try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: url)
}

/// The folder named by `variable`, created when needed. Skips the test when the variable is not set.
func pictureFolder(_ variable: String, skipMessage: String) throws -> URL {
    guard let path = ProcessInfo.processInfo.environment[variable] else { throw XCTSkip(skipMessage) }
    let folder = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

/// Writes `name-light.png` and `name-dark.png` to `folder`.
@MainActor
func writePictures(of parts: [(view: NSView, origin: NSPoint)], size: NSSize,
                   backdrop: NSColor = .windowBackgroundColor, named name: String, in folder: URL) throws {
    for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        try writePicture(of: parts, size: size, backdrop: backdrop, appearance: appearance,
                         to: folder.appendingPathComponent("\(name)-\(suffix).png"))
    }
}

@MainActor
func writePictures(of view: NSView, named name: String, in folder: URL) throws {
    try writePictures(of: [(view, .zero)], size: view.bounds.size, named: name, in: folder)
}
