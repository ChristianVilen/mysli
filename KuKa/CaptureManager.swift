import Cocoa
import UniformTypeIdentifiers
import UserNotifications

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
        playShutterSound()
        sendNotification()

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

    func generateFileName(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'_at_'HH-mm-ss"
        return "Screenshot_\(formatter.string(from: date)).png"
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

    private func playShutterSound() {
        NSSound(named: "Tink")?.play()
    }

    private func sendNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Ku-Ka"
        content.body = "Screenshot saved and copied!"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
