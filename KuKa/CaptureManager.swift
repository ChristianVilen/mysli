import Cocoa
import UniformTypeIdentifiers

// MARK: - Protocols

protocol FileManaging {
    var homeDirectoryForCurrentUser: URL { get }
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey: Any]?) throws
    func writeImageData(_ data: Data, to url: URL) throws
}

protocol ClipboardManaging {
    func copyImage(tiffData: Data, pngData: Data)
}

protocol ScreenCapturing {
    func captureScreen(rect: CGRect) -> CGImage?
}

// MARK: - Real Implementations

extension FileManager: FileManaging {
    func writeImageData(_ data: Data, to url: URL) throws {
        try data.write(to: url)
    }
}

class SystemClipboard: ClipboardManaging {
    func copyImage(tiffData: Data, pngData: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(tiffData, forType: .tiff)
        pb.setData(pngData, forType: .png)
    }
}

class SystemScreenCapture: ScreenCapturing {
    func captureScreen(rect: CGRect) -> CGImage? {
        CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution)
    }
}

// MARK: - CaptureResult

struct CaptureResult {
    let image: NSImage
    let fileURL: URL
}

// MARK: - CaptureManager

class CaptureManager {
    let fileManager: FileManaging
    let clipboard: ClipboardManaging
    let screenCapture: ScreenCapturing

    init(fileManager: FileManaging = FileManager.default,
         clipboard: ClipboardManaging = SystemClipboard(),
         screenCapture: ScreenCapturing = SystemScreenCapture()) {
        self.fileManager = fileManager
        self.clipboard = clipboard
        self.screenCapture = screenCapture
    }

    func capture(rect: CGRect, screen: NSScreen) -> CaptureResult? {
        let screenFrame = screen.frame
        let cgRect = CGRect(
            x: screenFrame.origin.x + rect.origin.x,
            y: screenFrame.height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )

        guard let cgImage = screenCapture.captureScreen(rect: cgRect) else {
            NSLog("Ku-Ka: Screen capture returned nil")
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let fileURL = saveToDisk(cgImage: cgImage)
        copyToClipboard(image: image)

        return CaptureResult(image: image, fileURL: fileURL)
    }

    func saveAnnotated(image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? fileManager.writeImageData(png, to: url)
        copyToClipboard(image: image)
    }

    func copyToClipboard(image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        clipboard.copyImage(tiffData: tiff, pngData: png)
    }

    func screenshotsDirectory() -> URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Screenshots")
    }

    private func dateString(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'_at_'HH-mm-ss"
        return formatter.string(from: date)
    }

    func generateFileName(for date: Date = Date()) -> String {
        "Screenshot_\(dateString(for: date)).png"
    }

    func generateCombinedFileName(for date: Date = Date()) -> String {
        "Screenshot_\(dateString(for: date))_combined.png"
    }

    func saveCombined(topImage: NSImage, bottomImage: NSImage) -> CaptureResult? {
        let width = max(topImage.size.width, bottomImage.size.width)
        let height = topImage.size.height + bottomImage.size.height
        let combined = NSImage(size: NSSize(width: width, height: height))

        combined.lockFocus()
        topImage.draw(in: NSRect(x: 0, y: bottomImage.size.height, width: topImage.size.width, height: topImage.size.height))
        bottomImage.draw(in: NSRect(x: 0, y: 0, width: bottomImage.size.width, height: bottomImage.size.height))
        combined.unlockFocus()

        guard let tiff = combined.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }

        let dir = screenshotsDirectory()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        let url = dir.appendingPathComponent(generateCombinedFileName())
        try? fileManager.writeImageData(pngData, to: url)
        copyToClipboard(image: combined)

        return CaptureResult(image: combined, fileURL: url)
    }

    private func saveToDisk(cgImage: CGImage) -> URL {
        let dir = screenshotsDirectory()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)

        let url = dir.appendingPathComponent(generateFileName())

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        if let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            try? fileManager.writeImageData(pngData, to: url)
        }
        return url
    }

}
