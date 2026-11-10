import XCTest
@testable import Mysli

final class TeamsWebContentSwitchTests: XCTestCase {
    func testTurnsOnEachTeamsProcessOnceAndOffAgainAtTheEnd() {
        let flags = FakeTeamsFlags(processes: [10], flags: [10: false])
        let webContent = TeamsWebContentSwitch(port: flags, log: { _ in })
        webContent.turnOn()
        webContent.turnOn()
        flags.processes = [10, 20]
        webContent.turnOn()
        webContent.restore()
        XCTAssertEqual(flags.writes, [.init(10, true), .init(20, true), .init(10, false), .init(20, false)])
    }

    func testLeavesAFlagThatWasAlreadyOn() {
        let flags = FakeTeamsFlags(processes: [10], flags: [10: true])
        let webContent = TeamsWebContentSwitch(port: flags, log: { _ in })
        webContent.turnOn()
        webContent.restore()
        XCTAssertEqual(flags.writes, [])
    }

    func testWritesOnlyWithAccessibilityAndTriesAgainWhenItIsGranted() {
        let flags = FakeTeamsFlags(processes: [10], flags: [:])
        flags.trusted = false
        let webContent = TeamsWebContentSwitch(port: flags, log: { _ in })
        webContent.turnOn()
        XCTAssertEqual(flags.writes, [])
        flags.trusted = true
        webContent.turnOn()
        XCTAssertEqual(flags.writes, [.init(10, true)])
    }

    func testTurnsOffOnlyProcessesThatStillRun() {
        let flags = FakeTeamsFlags(processes: [10, 20], flags: [10: false, 20: false])
        let webContent = TeamsWebContentSwitch(port: flags, log: { _ in })
        webContent.turnOn()
        flags.processes = [20, 30]
        webContent.restore()
        XCTAssertEqual(flags.writes, [.init(10, true), .init(20, true), .init(20, false)])
    }

    func testSourceTurnsTheFlagOnBeforeEachScanAndOffWhenItFinishes() {
        let flags = FakeTeamsFlags(processes: [10], flags: [10: false])
        let scans = ScanCounter(flags: flags)
        let source = TeamsWebContentSource(source: scans,
                                           webContent: TeamsWebContentSwitch(port: flags, log: { _ in }))
        _ = source.snapshot()
        _ = source.snapshot()
        source.finish()
        XCTAssertEqual(scans.flagDuringScans, [true, true])
        XCTAssertEqual(flags.writes, [.init(10, true), .init(10, false)])
    }

    func testChecksEachProcessAgainAfterRestore() {
        let flags = FakeTeamsFlags(processes: [10], flags: [10: false])
        let webContent = TeamsWebContentSwitch(port: flags, log: { _ in })
        webContent.turnOn()
        webContent.restore()
        webContent.turnOn()
        XCTAssertEqual(flags.writes, [.init(10, true), .init(10, false), .init(10, true)])
    }
}

private final class ScanCounter: TeamsSnapshotReading {
    private let flags: FakeTeamsFlags
    private(set) var flagDuringScans: [Bool?] = []
    init(flags: FakeTeamsFlags) { self.flags = flags }
    func snapshot() -> TeamsAXSnapshot {
        flagDuringScans.append(flags.flags[10])
        return TeamsAXSnapshot(result: .unnamed(.noHighlightedTile))
    }
}

private final class FakeTeamsFlags: TeamsAppFlagPort {
    struct Write: Equatable {
        let pid: pid_t
        let on: Bool
        init(_ pid: pid_t, _ on: Bool) {
            self.pid = pid
            self.on = on
        }
    }

    var trusted = true
    var processes: [pid_t]
    var flags: [pid_t: Bool]
    private(set) var writes: [Write] = []

    init(processes: [pid_t], flags: [pid_t: Bool]) {
        self.processes = processes
        self.flags = flags
    }

    func isTrusted() -> Bool { trusted }
    func teamsProcesses() -> [pid_t] { processes }
    func enhancedUserInterface(_ pid: pid_t) -> Bool? { flags[pid] }
    func setEnhancedUserInterface(_ pid: pid_t, _ on: Bool) {
        writes.append(Write(pid, on))
        flags[pid] = on
    }
}
