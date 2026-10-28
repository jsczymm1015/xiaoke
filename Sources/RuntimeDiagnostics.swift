import Foundation
import CoreGraphics
import Darwin

/// Bounded lifecycle diagnostics; never includes tasks, clipboard, file text, or account data.
final class RuntimeDiagnostics {
    let directory: URL
    private let clock: () -> Date
    private let sessionID = UUID().uuidString
    private var lastHeartbeat = Date.distantPast
    private let maximumLogBytes = 65_536

    init(directory: URL, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.clock = now
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let previous = try? Data(contentsOf: directory.appendingPathComponent("runtime-status.json"))
        if let previous, let object = try? JSONSerialization.jsonObject(with: previous) as? [String: Any],
           object["closed"] as? Bool == false {
            record("previous-session-not-marked-closed", details: ["lastHeartbeat": object["timestamp"] as? String ?? "unknown"])
        }
    }

    func record(_ event: String, details: [String: String] = [:]) {
        var safeDetails: [String: String] = [:]
        for key in details.keys.sorted().prefix(10) {
            safeDetails[String(key.prefix(80))] = String((details[key] ?? "").prefix(300))
        }
        let row: [String: Any] = ["timestamp": stamp(), "session": sessionID,
                                  "pid": getpid(), "event": String(event.prefix(100)), "details": safeDetails]
        guard var data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        data.append(10)
        let url = directory.appendingPathComponent("runtime-events.jsonl")
        var existing = (try? Data(contentsOf: url)) ?? Data()
        if existing.count + data.count > maximumLogBytes {
            // Rotate only this generated log, never the companion save or user files.
            try? existing.write(to: directory.appendingPathComponent("runtime-events.previous.jsonl"), options: [.atomic])
            existing = Data()
        }
        existing.append(data)
        try? existing.write(to: url, options: [.atomic])
    }

    func heartbeat(petVisible: Bool, windowVisible: Bool, frame: CGRect, screens: Int, force: Bool = false, closed: Bool = false) {
        let now = clock()
        guard force || closed || now.timeIntervalSince(lastHeartbeat) >= 60 else { return }
        lastHeartbeat = now
        let row: [String: Any] = ["timestamp": stamp(), "session": sessionID, "pid": getpid(), "parentPID": getppid(),
            "closed": closed, "petEnabled": petVisible, "petWindowVisible": windowVisible, "screenCount": screens,
            "frame": ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]]
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: directory.appendingPathComponent("runtime-status.json"), options: [.atomic])
    }

    private func stamp() -> String { ISO8601DateFormatter().string(from: clock()) }
}
