import Cocoa
import ScreenCaptureKit
import UniformTypeIdentifiers

// MARK: - Protocols

protocol ScreenCapturing {
    func captureScreen(rect: CGRect) async -> CGImage?
    func captureWindow(windowID: CGWindowID) async -> CGImage?
}

class SystemScreenCapture: ScreenCapturing {
    /// `rect` is in CG global coordinates (top-left origin), same contract as
    /// the old CGWindowListCreateImage-based implementation.
    func captureScreen(rect: CGRect) async -> CGImage? {
        guard let content = await shareableContent() else { return nil }
        guard let display = content.displays.first(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) })
                ?? content.displays.first else {
            NSLog("Ku-Ka: No display found for capture rect")
            return nil
        }

        let sourceRect = CGRect(
            x: rect.origin.x - display.frame.origin.x,
            y: rect.origin.y - display.frame.origin.y,
            width: rect.width,
            height: rect.height
        )
        return await capture(filter: SCContentFilter(display: display, excludingWindows: []),
                             sourceRect: sourceRect,
                             pointSize: sourceRect.size,
                             label: "Screen capture")
    }

    func captureWindow(windowID: CGWindowID) async -> CGImage? {
        guard let content = await shareableContent() else { return nil }
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            NSLog("Ku-Ka: Window \(windowID) not found for capture")
            return nil
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        return await capture(filter: filter,
                             sourceRect: nil,
                             pointSize: filter.contentRect.size,
                             label: "Window capture")
    }

    private func shareableContent() async -> SCShareableContent? {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            NSLog("Ku-Ka: Shareable content lookup failed: \(error)")
            return nil
        }
    }

    /// Shared capture policy: cursor-free, best resolution, pixel size derived
    /// from the filter's point-to-pixel scale.
    private func capture(filter: SCContentFilter, sourceRect: CGRect?, pointSize: CGSize, label: String) async -> CGImage? {
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        if let sourceRect {
            config.sourceRect = sourceRect
        }
        config.width = Int(pointSize.width * scale)
        config.height = Int(pointSize.height * scale)
        config.showsCursor = false
        config.captureResolution = .best

        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            NSLog("Ku-Ka: \(label) failed: \(error)")
            return nil
        }
    }
}

// MARK: - CaptureResult

struct CaptureResult {
    let image: NSImage
    let fileURL: URL
}

// MARK: - CaptureManager

class CaptureManager {
    let screenCapture: ScreenCapturing
    let store: ImageStoring

    init(screenCapture: ScreenCapturing = SystemScreenCapture(),
         store: ImageStoring = ImageStore()) {
        self.screenCapture = screenCapture
        self.store = store
    }

    func captureFullScreen(screenFrame: CGRect, primaryHeight: CGFloat) async -> CaptureResult? {
        let cgRect = ScreenCoordinates.flipVertical(screenFrame, primaryScreenHeight: primaryHeight)

        guard let cgImage = await screenCapture.captureScreen(rect: cgRect) else {
            NSLog("Ku-Ka: Full screen capture returned nil")
            return nil
        }

        return store.store(cgImage: cgImage)
    }

    func captureWindow(windowID: CGWindowID) async -> CaptureResult? {
        guard let cgImage = await screenCapture.captureWindow(windowID: windowID) else {
            NSLog("Ku-Ka: Window capture returned nil")
            return nil
        }
        return store.store(cgImage: cgImage)
    }

    func capture(rect: CGRect, screenFrame: CGRect, primaryHeight: CGFloat) async -> CaptureResult? {
        let cgRect = ScreenCoordinates.cgRect(forSelection: rect, inScreenFrame: screenFrame, primaryHeight: primaryHeight)

        guard let cgImage = await screenCapture.captureScreen(rect: cgRect) else {
            NSLog("Ku-Ka: Screen capture returned nil")
            return nil
        }

        return store.store(cgImage: cgImage)
    }
}
