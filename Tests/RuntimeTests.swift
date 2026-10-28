import Foundation
import CoreGraphics

@main struct RuntimeTests {
    static func expect(_ condition: @autoclosure () throws -> Bool) throws {
        guard try condition() else { throw NSError(domain: "RuntimeTests", code: 1) }
    }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("xiaoke-runtime-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let save = root.appendingPathComponent("companion-state.json")
        let sentinel = Data("existing companion save".utf8)
        try sentinel.write(to: save)
        var now = Date(timeIntervalSince1970: 1_792_000_000)
        let runtime = RuntimeDiagnostics(directory: root, now: { now })
        let frame = CGRect(x: 40, y: 60, width: 250, height: 296)
        runtime.record("launched", details: ["mode": "normal"])
        runtime.heartbeat(petVisible: true, windowVisible: true, frame: frame, screens: 2)
        let statusURL = root.appendingPathComponent("runtime-status.json")
        let first = try Data(contentsOf: statusURL)
        let status = try JSONSerialization.jsonObject(with: first) as! [String: Any]
        try expect(status["closed"] as? Bool == false && status["screenCount"] as? Int == 2)
        now += 20
        runtime.heartbeat(petVisible: false, windowVisible: false, frame: frame, screens: 1)
        try expect(try Data(contentsOf: statusURL) == first)
        now += 41
        runtime.heartbeat(petVisible: false, windowVisible: false, frame: frame, screens: 1)
        try expect(try Data(contentsOf: statusURL) != first)
        _ = RuntimeDiagnostics(directory: root, now: { now })
        let logURL = root.appendingPathComponent("runtime-events.jsonl")
        try expect(try String(contentsOf: logURL, encoding: .utf8).contains("previous-session-not-marked-closed"))
        runtime.record("clean-exit")
        runtime.heartbeat(petVisible: false, windowVisible: false, frame: frame, screens: 1, closed: true)
        let closedLog = try Data(contentsOf: logURL)
        _ = RuntimeDiagnostics(directory: root, now: { now })
        try expect(try Data(contentsOf: logURL) == closedLog)
        for _ in 0..<300 { runtime.record("test", details: ["bounded": String(repeating: "x", count: 4000)]) }
        try expect(try Data(contentsOf: logURL).count <= 65_536)
        try expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("runtime-events.previous.jsonl").path))
        try expect(try Data(contentsOf: save) == sentinel)
        print("PASS: runtime heartbeat throttle, clean/unclean sessions, bounded log rotation, companion save preserved")
    }
}
