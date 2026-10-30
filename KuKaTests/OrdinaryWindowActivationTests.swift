import XCTest
@testable import KuKa

@MainActor
final class OrdinaryWindowActivationTests: XCTestCase {
    private var policies: [NSApplication.ActivationPolicy] = []
    private var activations = 0
    private var sut: OrdinaryWindowActivation!

    override func setUp() async throws {
        sut = .fake(setPolicy: { [unowned self] in policies.append($0) }, activateApp: { [unowned self] in activations += 1 })
    }

    func testTheAppStaysRegularUntilTheLastWindowClosesInEitherOrder() {
        for firstCloses in [true, false] {
            policies = []
            let first = NSWindow()
            let second = NSWindow()
            sut.open(first)
            sut.open(second)
            sut.close(firstCloses ? first : second)
            XCTAssertEqual(policies, [.regular])
            sut.close(firstCloses ? second : first)
            XCTAssertEqual(policies, [.regular, .accessory])
        }
    }

    func testEveryOpenBringsTheAppForwardButSetsThePolicyOnce() {
        let window = NSWindow()
        sut.open(window)
        sut.open(window)
        XCTAssertEqual(activations, 2)
        XCTAssertEqual(policies, [.regular])
        sut.close(window)
        XCTAssertEqual(policies, [.regular, .accessory])
    }

    func testClosingAWindowThatIsNotOpenChangesNothing() {
        let open = NSWindow()
        sut.close(open)
        sut.open(open)
        sut.close(NSWindow())
        XCTAssertEqual(policies, [.regular])
        sut.close(open)
        sut.close(open)
        XCTAssertEqual(policies, [.regular, .accessory])
    }
}
