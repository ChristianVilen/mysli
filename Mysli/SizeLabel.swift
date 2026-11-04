import Cocoa

/// Style of the "W × H" badge that the selection overlay and the crop
/// overlay both draw, so a font or colour change happens in one place.
enum SizeLabel {
    static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white,
        .backgroundColor: NSColor.black.withAlphaComponent(0.7)
    ]
}
