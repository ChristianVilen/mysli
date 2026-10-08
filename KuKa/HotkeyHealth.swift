/// Registration success does not prove that a capture, window move, or paste succeeds.
struct HotkeyHealth: Equatable {
    var accessibilityMissing = false
    var issues: [HotkeyRegistrationIssue] = []
    static let healthy = HotkeyHealth()
}
