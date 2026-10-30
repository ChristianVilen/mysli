import Foundation

final class FakeAX: ProbeAX {
    var calls: [String] = []
    var allowed = true
    var bundle = "com.microsoft.teams2"
    var title = "Meeting"
    var role = "AXButton"
    var selected: Any = "Alice"
    var failure: Int32?
    var childCount = 45
    var tick: UInt64 = 100
    func bundleID(pid: Int32) -> String? { calls.append("bundle"); return bundle }
    func trusted() -> Bool { calls.append("trusted"); return allowed }
    func focusedWindow(pid: Int32) throws -> Int {
        calls.append("window")
        if let failure { throw ProbeFailure.ax(failure) }
        return 0
    }
    func value(_ node: Int, _ attribute: String) throws -> Any {
        calls.append("value:\(node):\(attribute)")
        if attribute == "AXTitle" && node == 0 { return title }
        if attribute == "AXRole" { return node == 0 ? "AXWindow" : role }
        if attribute == "AXDescription" { return selected }
        return "CHAT SECRET"
    }
    func attributes(_ node: Int) throws -> [String] {
        calls.append("attributes:\(node)")
        return ["AXRole", "AXTitle", "AXDescription", "AXValue"]
    }
    func children(_ node: Int, start: Int, count: Int) throws -> [Int] {
        calls.append("children:\(node):\(start):\(count)")
        return (start..<min(start + count, max(start, childCount))).map { $0 + 1 }
    }
    func clock() -> UInt64 { calls.append("clock"); defer { tick += 1 }; return tick }
}

@main struct ProbeTests {
    static func main() {
        var failed = 0
        var count = 0
        func check(_ name: String, _ body: () -> Bool) {
            count += 1
            if body() { print("PASS \(name)") } else { print("FAIL \(name)"); failed += 1 }
        }
        let base = ["--pid", "123", "--window-title", "Meeting", "--confirm", "--mode", "structure", "--path", ""]
        func replacing(_ key: String, _ value: String) -> [String] {
            var args = base
            args[args.firstIndex(of: key)! + 1] = value
            return args
        }
        for (name, args) in [
            ("missing confirmation", base.filter { $0 != "--confirm" }),
            ("empty title", replacing("--window-title", "  ")),
            ("zero PID", replacing("--pid", "0")),
            ("overflow PID", replacing("--pid", "999999999999")),
            ("negative path", replacing("--path", "-1")),
            ("malformed path", replacing("--path", "0..1")),
            ("excessive path", replacing("--path", Array(repeating: "0", count: 31).joined(separator: "."))),
            ("invalid mode", replacing("--mode", "scan")),
            ("unknown option", base + ["--scan", "yes"]),
            ("duplicate option", base + ["--pid", "456"]),
            ("read root", replacing("--mode", "read") + ["--attribute", "AXRole"]),
            ("disallowed attribute", ["--pid", "123", "--window-title", "Meeting", "--confirm", "--mode", "read", "--path", "0", "--attribute", "AXURL"]),
            ("structure attribute", base + ["--attribute", "AXValue"])
        ] {
            check(name) { let ax = FakeAX(); return probe(args, ax: ax).hasPrefix("refused:") && ax.calls.isEmpty }
        }
        check("help avoids AX") { let ax = FakeAX(); return probe(["--help"], ax: ax).contains("--confirm") && ax.calls.isEmpty }
        check("permission denied") { let ax = FakeAX(); ax.allowed = false; return probe(base, ax: ax) == "refused: Accessibility permission required" && !ax.calls.contains("window") }
        check("wrong app") { let ax = FakeAX(); ax.bundle = "other"; return probe(base, ax: ax) == "refused: PID is not Teams" && !ax.calls.contains("window") }
        check("wrong title stays private") { let ax = FakeAX(); ax.title = "CHAT SECRET"; return probe(base, ax: ax) == "refused: focused window does not match" && !ax.calls.contains("attributes:0") }
        check("path uses one child per step") { let ax = FakeAX(); let out = probe(replacing("--path", "4.2"), ax: ax); return out.contains("role=\"AXButton\"") && ax.calls.contains("children:0:4:1") && ax.calls.contains("children:5:2:1") }
        check("missing path child refuses") { let ax = FakeAX(); ax.childCount = 0; return probe(replacing("--path", "3"), ax: ax) == "refused: path index out of range" }
        check("structure hides text and limits children") { let ax = FakeAX(); let out = probe(base, ax: ax); return out.contains("39 role=\"AXButton\"") && !out.contains("40 role=") && !out.contains("CHAT SECRET") && ax.calls.contains("children:0:0:40") && !ax.calls.contains("value:1:AXTitle") && !ax.calls.contains("value:1:AXDescription") }
        let read = ["--pid", "123", "--window-title", "Meeting", "--confirm", "--mode", "read", "--path", "0", "--attribute", "AXDescription"]
        check("reads selected attribute with clock bounds") {
            let ax = FakeAX()
            return probe(read, ax: ax) == "before_host_ticks=100\nafter_host_ticks=101\nAXDescription=\"Alice\"" && ax.calls == [
                "bundle", "trusted", "window", "value:0:AXTitle", "children:0:0:1",
                "value:1:AXRole", "clock", "value:1:AXDescription", "clock"
            ]
        }
        for role in ["AXTextField", "AXTextArea", "AXSecureTextField"] {
            check("rejects \(role)") { let ax = FakeAX(); ax.role = role; return probe(read, ax: ax) == "refused: text input node" && !ax.calls.contains("value:1:AXDescription") }
        }
        for (name, value, expected) in [("boolean", true as Any, "true"), ("number", 42 as Any, "42"), ("array", ["Alice", "Bob"] as Any, "[\"Alice\",\"Bob\"]")] {
            check("formats \(name)") { let ax = FakeAX(); ax.selected = value; return probe(read, ax: ax).hasSuffix("AXDescription=\(expected)") }
        }
        check("rejects complex values") { let ax = FakeAX(); ax.selected = ["secret": "CHAT SECRET"]; return probe(read, ax: ax) == "refused: unsupported attribute value" }
        check("bounds strings") { let ax = FakeAX(); ax.selected = String(repeating: "x", count: 3000); return probe(read, ax: ax) == "refused: attribute value exceeds output limit" }
        check("reports AX code") { let ax = FakeAX(); ax.failure = -25204; return probe(base, ax: ax) == "AX error -25204" }
        print("\(count - failed)/\(count) passed")
        exit(failed == 0 ? 0 : 1)
    }
}
