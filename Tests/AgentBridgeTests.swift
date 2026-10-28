import Foundation

@main struct AgentBridgeTests {
    static func main() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var now = Date(timeIntervalSince1970: 1000)
        let reader = AgentInboxReader(directory: dir, now: { now })
        var assertions = 0
        func check(_ ok: Bool, _ message: String) throws {
            assertions += 1
            if !ok { throw NSError(domain: "AgentBridgeTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func write(_ provider: String = "test", task: String = "one", status: String = "started", time: Double = 1000, ttl: Double = 45,
                   version: Int = 1, completed: Int? = nil, total: Int? = nil, file: String = "one.json") throws {
            let event = AgentWireEvent(version: version, eventID: UUID().uuidString, provider: provider, taskID: task, status: status,
                title: "Sample task", timestamp: time, ttl: ttl, phase: "editing", completed: completed, total: total)
            try JSONEncoder().encode(event).write(to: dir.appendingPathComponent(file), options: .atomic)
        }
        try write()
        try check(reader.poll().tasks.count == 1, "start becomes active")
        try check(reader.poll().events.isEmpty, "polling does not emit duplicate lifecycle events")
        try write(status: "waiting")
        try check(reader.poll().tasks.first?.phase == .waiting, "waiting state is explicit")
        try write(status: "progress", completed: 2, total: 3)
        try check(reader.poll().tasks.first?.completedPlanSteps == 2, "progress counts retained")
        try write("other", task: "one", file: "two.json")
        try check(reader.poll().tasks.count == 2, "providers cannot collide")
        try write(status: "completed")
        let done = reader.poll()
        try check(done.tasks.count == 1 && done.events.first?.kind == .completed, "completion only removes matching task")
        try check(reader.poll().events.isEmpty, "completion delivered once")
        now = Date(timeIntervalSince1970: 1100)
        let expired = reader.poll()
        try check(expired.tasks.isEmpty && expired.events.isEmpty, "expiry never fabricates completion")
        try write(time: 1200)
        try check(reader.poll().tasks.isEmpty, "reject future events")
        try write(time: 1100, version: 99)
        try check(reader.poll().tasks.isEmpty, "reject unknown protocol version")
        try write("../escape", time: 1100)
        try check(reader.poll().tasks.isEmpty, "reject invalid provider")
        try write(status: "progress", time: 1100, completed: 9, total: 2)
        try check(reader.poll().tasks.first?.totalPlanSteps == nil, "invalid counts never shown")
        try write(status: "failed", time: 1100)
        try check(reader.poll().events.first?.kind == .failed, "failure mapped")
        try write(status: "interrupted", time: 1100)
        try check(reader.poll().events.first?.kind == .interrupted, "interruption not completion")
        try Data(repeating: 65, count: 4097).write(to: dir.appendingPathComponent("one.json"))
        try check(reader.poll().tasks.isEmpty, "oversized input rejected")
        try Data("broken json".utf8).write(to: dir.appendingPathComponent("one.json"))
        try check(reader.poll().tasks.isEmpty, "partial input ignored")
        print("PASS: \(assertions) Agent bridge assertions")
    }
}
