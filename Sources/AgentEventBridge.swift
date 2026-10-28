import Foundation

/// Public v1 protocol: one atomic snapshot per provider/task; never command output.
struct AgentWireEvent: Codable {
    let version: Int
    let eventID: String
    let provider: String
    let taskID: String
    let status: String
    let title: String
    let timestamp: Double
    let ttl: Double
    let phase: String?
    let completed: Int?
    let total: Int?
}

struct ExternalAgentSnapshot {
    var tasks: [AgentActiveTask] = []
    var events: [AgentTaskEvent] = []
}

/// Runs on the sampler queue. No sockets or network listeners; only owner-local files.
final class AgentInboxReader {
    let directory: URL
    private let now: () -> Date
    private var seen: [String: String] = [:]
    private var starts: [String: Date] = [:]
    init(directory: URL, now: @escaping () -> Date = Date.init) { self.directory = directory; self.now = now }
    func reset() { seen.removeAll(); starts.removeAll() }
    func poll() -> ExternalAgentSnapshot {
        var snapshot = ExternalAgentSnapshot()
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles])) ?? []
        var present = Set<String>()
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).prefix(256) {
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 4096,
                  let data = try? Data(contentsOf: file), data.count <= 4096,
                  let event = try? JSONDecoder().decode(AgentWireEvent.self, from: data),
                  event.version == 1, validID(event.provider), validID(event.taskID), validID(event.eventID),
                  event.title.count <= 120, !event.title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  event.timestamp.isFinite, event.ttl.isFinite, event.ttl >= 5, event.ttl <= 86400,
                  ["started", "progress", "waiting", "completed", "failed", "interrupted"].contains(event.status) else { continue }
            let age = now().timeIntervalSince1970 - event.timestamp
            guard age >= -30, age <= event.ttl else { continue }
            let key = "external:\(event.provider):\(event.taskID)"
            present.insert(key)
            let date = Date(timeIntervalSince1970: event.timestamp)
            let fresh = seen[key] != event.eventID
            if fresh && event.status == "started" { starts[key] = date }
            seen[key] = event.eventID
            if ["started", "progress", "waiting"].contains(event.status) {
                let total = event.total.flatMap { $0 > 0 && $0 <= 10000 ? $0 : nil }
                let completed = event.completed.flatMap { value in total.flatMap { value >= 0 && value <= $0 ? value : nil } }
                snapshot.tasks.append(AgentActiveTask(threadID: key, turnID: event.taskID,
                    title: "[\(event.provider)] \(event.title)", startedAt: starts[key] ?? date, updatedAt: date,
                    phase: event.status == "waiting" ? .waiting : (AgentTaskPhase(rawValue: event.phase ?? "") ?? .executing),
                    completedPlanSteps: completed, totalPlanSteps: completed == nil ? nil : total))
                if starts[key] == nil { starts[key] = date }
            } else if fresh, let kind = AgentTaskEventKind(rawValue: event.status) {
                snapshot.events.append(AgentTaskEvent(threadID: key, turnID: event.eventID, kind: kind, occurredAt: date))
                starts.removeValue(forKey: key)
            }
        }
        seen = seen.filter { present.contains($0.key) }
        starts = starts.filter { present.contains($0.key) }
        snapshot.tasks.sort { $0.startedAt < $1.startedAt }
        return snapshot
    }
    private func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0)
        }
    }
}
