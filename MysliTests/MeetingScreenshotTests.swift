import Cocoa
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Mysli

final class MeetingScreenshotTests: XCTestCase {
    func testImportConvertsTIFFToPNGAndRejectsInvalidBytes() throws {
        let image = try MeetingScreenshot.decode(bitmap(width: 80, height: 40, type: .tiff))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(image.png as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.png.identifier)
        XCTAssertEqual(CGImageSourceCreateImageAtIndex(source, 0, nil)?.width, 80)
        XCTAssertThrowsError(try MeetingScreenshot.decode(Data("bad image".utf8)))
        let png = try bitmap(width: 80, height: 40)
        XCTAssertThrowsError(try MeetingScreenshot.decode(png, within: .init(bytes: png.count - 1)))
        XCTAssertThrowsError(try MeetingScreenshot.decode(bitmap(width: 101, height: 1), within: .init(pixelsPerSide: 100)))
        XCTAssertThrowsError(try MeetingScreenshot.decode(png, within: .init(pixels: 80 * 40 - 1)))
    }

    func testStoreRoundTripRejectsUnsafeNamesAndSymlinks() throws {
        let root = try makeTemporaryDirectory()
        let meeting = try MeetingFolder.create(in: root, startingAt: Date())
        let store = MeetingScreenshotStore(meeting: meeting)
        let image = try MeetingScreenshot.decode(bitmap(width: 80, height: 40))
        let name = try store.write(image)
        XCTAssertEqual(store.read(named: name), image.png)
        XCTAssertNil(store.read(named: "../" + name))
        let file = meeting.url.appendingPathComponent("attachments").appendingPathComponent(name)
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        XCTAssertEqual(try MeetingScreenshot.read(from: file).png.prefix(8), image.png.prefix(8))
        XCTAssertThrowsError(try MeetingScreenshot.read(from: meeting.url))
        XCTAssertThrowsError(try MeetingScreenshot.read(from: URL(string: "https://example.com/image.png")!))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 20_000_001)
        try handle.close()
        XCTAssertNil(store.read(named: name))
        XCTAssertThrowsError(try MeetingScreenshot.read(from: file))
        try Data("corrupt".utf8).write(to: file)
        XCTAssertNil(MeetingScreenshotThumbnails(store: store).thumbnail(named: name))
        try FileManager.default.removeItem(at: file)
        let target = root.appendingPathComponent("outside.png")
        try image.png.write(to: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        XCTAssertNil(store.read(named: name))
        XCTAssertThrowsError(try MeetingScreenshot.read(from: file))
    }

    func testStoreRejectsSymlinkedAttachmentsDirectory() throws {
        let root = try makeTemporaryDirectory()
        let meeting = try MeetingFolder.create(in: root, startingAt: Date())
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: meeting.url.appendingPathComponent("attachments"), withDestinationURL: outside)
        let image = try MeetingScreenshot.decode(bitmap(width: 10, height: 10))
        XCTAssertThrowsError(try MeetingScreenshotStore(meeting: meeting).write(image))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
    }

    func testThumbnailFitsBoxAndCachesAfterFileIsRemoved() throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: Date())
        let store = MeetingScreenshotStore(meeting: meeting)
        let name = try store.write(MeetingScreenshot.decode(bitmap(width: 800, height: 400)))
        let thumbnails = MeetingScreenshotThumbnails(store: store, box: NSSize(width: 100, height: 100))
        let thumbnail = try XCTUnwrap(thumbnails.thumbnail(named: name))
        XCTAssertEqual(thumbnail.size, NSSize(width: 100, height: 50))
        let representation = try XCTUnwrap(thumbnail.representations.first)
        XCTAssertEqual(representation.pixelsWide, 200)
        try FileManager.default.removeItem(at: meeting.url.appendingPathComponent("attachments").appendingPathComponent(name))
        XCTAssertTrue(thumbnails.thumbnail(named: name) === thumbnail)
        XCTAssertNil(thumbnails.thumbnail(named: "invalid.png"))
    }

    private func bitmap(width: Int, height: Int, type: UTType = .png) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
