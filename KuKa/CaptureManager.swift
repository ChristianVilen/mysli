import Cocoa
import UniformTypeIdentifiers
import UserNotifications

class CaptureManager {
    func capture(rect: CGRect, screen: NSScreen) {
        // Convert from NSView coordinates (bottom-left origin) to CGDisplay coordinates (top-left origin)
        let screenFrame = screen.frame
        let cgRect = CGRect(
            x: screenFrame.origin.x + rect.origin.x,
            y: screenFrame.height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )

        NSLog("Ku-Ka: selection rect=\(rect), cgRect=\(cgRect), screenFrame=\(screenFrame)")

        guard let cgImage = CGWindowListCreateImage(cgRect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution) else {
            NSLog("Ku-Ka: CGWindowListCreateImage returned nil")
            return
        }

        NSLog("Ku-Ka: captured image \(cgImage.width)x\(cgImage.height)")

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

        saveToDisk(cgImage: cgImage)
        copyToClipboard(image: image)
        playShutterSound()
        sendNotification()
    }

    private func saveToDisk(cgImage: CGImage) {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Screenshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'_at_'HH-mm-ss"
        let name = "Screenshot_\(formatter.string(from: Date())).png"
        let url = dir.appendingPathComponent(name)

        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
    }

    private func copyToClipboard(image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            NSLog("Ku-Ka: failed to create clipboard data")
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(tiff, forType: .tiff)
        pb.setData(png, forType: .png)
        NSLog("Ku-Ka: copied to clipboard (tiff=\(tiff.count) bytes, png=\(png.count) bytes)")
    }

    private func playShutterSound() {
        NSSound(named: "Tink")?.play()
    }

    private func sendNotification() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let content = UNMutableNotificationContent()
        content.title = "Ku-Ka"
        content.body = "Screenshot saved and copied!"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
}
