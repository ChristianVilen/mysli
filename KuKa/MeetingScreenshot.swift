import Cocoa
import Darwin
import ImageIO
import UniformTypeIdentifiers

struct MeetingScreenshot {
    let png: Data
    private static let maximumBytes = 20_000_000

    struct Limits {
        var bytes = MeetingScreenshot.maximumBytes
        var pixelsPerSide = 16_000
        var pixels = 40_000_000
    }

    private init(png: Data) { self.png = png }

    static func decode(_ data: Data, within limits: Limits = Limits()) throws -> Self {
        guard data.count <= limits.bytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...limits.pixelsPerSide).contains(width), (1...limits.pixelsPerSide).contains(height),
              width * height <= limits.pixels,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw MeetingStepError("Choose an image under 20 MB, 16,000 pixels per side, and 40 million pixels.")
        }
        let png = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else {
            throw MeetingStepError("Could not convert the screenshot to PNG.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), png.length <= limits.bytes else {
            throw MeetingStepError("The converted screenshot must be under 20 MB.")
        }
        return Self(png: png as Data)
    }

    static func read(from url: URL) throws -> Self {
        guard url.isFileURL else { throw MeetingStepError("Choose a local image file.") }
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw MeetingStepError("Could not open the screenshot file.") }
        defer { Darwin.close(descriptor) }
        return try decode(readBytes(descriptor))
    }

    fileprivate static func readBytes(_ descriptor: Int32) throws -> Data {
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0, info.st_size <= maximumBytes else {
            throw MeetingStepError("Choose a regular image file under 20 MB.")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw MeetingStepError("The screenshot must be under 20 MB.") }
        return data
    }
}

struct MeetingScreenshotStore {
    private let meeting: MeetingFolder

    init(meeting: MeetingFolder) { self.meeting = meeting }

    /// Only names that `write` makes, so a name from notes.md cannot reach another file.
    static func isValidName(_ name: String) -> Bool {
        name.hasSuffix(".png") && UUID(uuidString: String(name.dropLast(4))) != nil
    }

    func write(_ screenshot: MeetingScreenshot) throws -> String {
        let directory = try openDirectory(create: true)
        defer { Darwin.close(directory) }
        let name = UUID().uuidString + ".png"
        let descriptor = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw MeetingStepError("Could not save the screenshot.") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: screenshot.png)
            try handle.close()
        } catch {
            try? handle.close()
            unlinkat(directory, name, 0)
            throw error
        }
        return name
    }

    func read(named name: String) -> Data? {
        guard Self.isValidName(name), let directory = try? openDirectory(create: false) else { return nil }
        defer { Darwin.close(directory) }
        let descriptor = openat(directory, name, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }
        return try? MeetingScreenshot.readBytes(descriptor)
    }

    private func openDirectory(create: Bool) throws -> Int32 {
        let root = open(meeting.url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard root >= 0 else { throw MeetingStepError("Could not open the meeting folder.") }
        defer { Darwin.close(root) }
        if create, mkdirat(root, "attachments", 0o700) != 0, errno != EEXIST {
            throw MeetingStepError("Could not create the attachments folder.")
        }
        let directory = openat(root, "attachments", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard directory >= 0 else { throw MeetingStepError("Could not open the attachments folder.") }
        return directory
    }
}

final class MeetingScreenshotThumbnails {
    private let store: MeetingScreenshotStore
    private let box: NSSize
    private let cache = NSCache<NSString, NSImage>()

    init(store: MeetingScreenshotStore, box: NSSize = NSSize(width: 280, height: 140)) {
        self.store = store
        self.box = box
        cache.countLimit = 100
        cache.totalCostLimit = 32_000_000
    }

    func thumbnail(named name: String) -> NSImage? {
        if let image = cache.object(forKey: name as NSString) { return image }
        guard box.width > 0, box.height > 0,
              let data = store.read(named: name),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(max(box.width, box.height) * 2),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              cgImage.width > 0, cgImage.height > 0 else { return nil }
        let scale = min(box.width / CGFloat(cgImage.width), box.height / CGFloat(cgImage.height))
        let image = NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) * scale,
                                                        height: CGFloat(cgImage.height) * scale))
        cache.setObject(image, forKey: name as NSString, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }
}
