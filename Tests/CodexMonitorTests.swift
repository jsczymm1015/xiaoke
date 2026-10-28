import Foundation

@main struct CodexMonitorTests {
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw NSError(domain: "CodexMonitorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func jsonLine(_ value: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]); data.append(10); return data
    }
    static func metadata(_ id: String, source: Any = "vscode", threadSource: String? = "user") throws -> Data {
        var payload: [String: Any] = ["id": id, "source": source, "base_instructions": "PRIVATE-FIXTURE-TEXT"]
        if let threadSource { payload["thread_source"] = threadSource }
        return try jsonLine(["type": "session_meta", "payload": payload])
    }
    static func event(_ type: String, _ turn: String, at: Date, error: Any? = nil) throws -> Data {
        var payload: [String: Any] = ["type": type, "turn_id": turn, "last_agent_message": "PRIVATE-FIXTURE-TEXT"]
        if type == "task_started" { payload["started_at"] = at.timeIntervalSince1970 }
        else { payload["completed_at"] = at.timeIntervalSince1970 }
        if let error { payload["error"] = error }
        return try jsonLine(["type": "event_msg", "timestamp": ISO8601DateFormatter().string(from: at), "payload": payload])
    }
    static func append(_ data: Data, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: data)
    }
    static func toolRecord(_ type: String, name: String = "exec", callID: String, at: Date, arguments: String? = nil, turnID: String? = nil) throws -> Data {
        var payload: [String: Any] = ["type": type, "name": name, "call_id": callID]
        if type == "function_call" { payload["arguments"] = arguments ?? "PRIVATE-TOOL-CONTENT" }
        else if type == "custom_tool_call" { payload["input"] = arguments ?? "PRIVATE-TOOL-CONTENT" }
        else { payload["output"] = "PRIVATE-TOOL-CONTENT" }
        if let turnID { payload["turn_id"] = turnID }
        return try jsonLine(["type": "response_item", "timestamp": ISO8601DateFormatter().string(from: at), "payload": payload])
    }
    @MainActor static func main() async throws {
        if let index = CommandLine.arguments.firstIndex(of: "--live-observe") {
            let seconds = CommandLine.arguments.indices.contains(index + 1) ? Int(CommandLine.arguments[index + 1]) ?? 60 : 60
            let reader = CodexRolloutReader(rootURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions"), cursorDirectory: nil)
            let baseline = reader.begin()
            print("LIVE BASELINE connected=\(baseline.connected) active=\(baseline.activeCount); historical events suppressed")
            fflush(stdout)
            let deadline = Date().addingTimeInterval(Double(min(max(seconds, 2), 600)))
            var counts: [String: Int] = [:]
            var progressFingerprint = ""
            while Date() < deadline {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                let snapshot = reader.poll()
                let phases = snapshot.activeTasks.map { $0.phase.rawValue }.sorted().joined(separator: ",")
                let plans = snapshot.activeTasks.compactMap { task -> String? in
                    guard let completed = task.completedPlanSteps, let total = task.totalPlanSteps else { return nil }
                    return "\(completed)/\(total)"
                }.sorted().joined(separator: ",")
                let fingerprint = "active=\(snapshot.activeCount) phases=\(phases) plan_steps=\(plans)"
                if fingerprint != progressFingerprint {
                    print("LIVE PROGRESS \(fingerprint)"); fflush(stdout); progressFingerprint = fingerprint
                }
                for event in snapshot.events {
                    counts[event.kind.rawValue, default: 0] += 1
                    // Event kind and timestamp only; never emit thread titles, text, or full paths.
                    print("LIVE EVENT kind=\(event.kind.rawValue) at=\(ISO8601DateFormatter().string(from: event.occurredAt)) active=\(snapshot.activeCount)")
                    fflush(stdout)
                }
            }
            print("LIVE OBSERVATION COUNTS \(counts)")
            return
        }

        let fm = FileManager.default
        let fixture = fm.temporaryDirectory.appendingPathComponent("xiaoke-codex-monitor-tests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: fixture) }
        let sessions = fixture.appendingPathComponent("sessions")
        let cursors = fixture.appendingPathComponent("cursors")
        try fm.createDirectory(at: sessions, withIntermediateDirectories: true)
        var clock = Date(timeIntervalSince1970: 1_792_045_466)
        let file = sessions.appendingPathComponent("rollout-first.jsonl")
        var history = try metadata("thread-one")
        history.append(try event("task_started", "old-turn", at: clock.addingTimeInterval(-100)))
        history.append(try event("task_complete", "old-turn", at: clock.addingTimeInterval(-90), error: NSNull()))
        try history.write(to: file)
        let reader = CodexRolloutReader(rootURL: sessions, cursorDirectory: cursors, now: { clock })
        let baseline = reader.begin()
        try expect(baseline.connected && baseline.events.isEmpty && baseline.activeCount == 0, "Initial scan must not replay history")

        try append(event("task_started", "turn-one", at: clock), to: file)
        var result = reader.poll()
        try expect(result.events.map(\.kind) == [.started] && result.activeCount == 1, "Start metadata should mark one active task")
        let complete = try event("task_complete", "turn-one", at: clock, error: NSNull())
        try append(complete.prefix(complete.count / 2), to: file)
        try expect(reader.poll().events.isEmpty, "A partial JSON line cannot complete a task")
        try append(complete.suffix(complete.count - complete.count / 2), to: file)
        result = reader.poll()
        try expect(result.events.map(\.kind) == [.completed] && result.activeCount == 0, "Complete null error should complete exactly once")
        try append(complete, to: file)
        try append(event("task_complete", "turn-one", at: clock, error: ["message": "PRIVATE-FIXTURE-TEXT"]), to: file)
        try expect(reader.poll().events.isEmpty, "Repeated/conflicting terminal events for the same turn must be ignored")

        try append(event("task_started", "turn-error", at: clock), to: file)
        try append(event("task_complete", "turn-error", at: clock, error: ["message": "PRIVATE-FIXTURE-TEXT"]), to: file)
        result = reader.poll()
        try expect(result.events.map(\.kind) == [.started, .failed] && result.activeCount == 0, "A non-null error is a failure")
        try append(event("task_started", "turn-interrupt", at: clock), to: file)
        try append(event("turn_aborted", "turn-interrupt", at: clock), to: file)
        try expect(reader.poll().events.map(\.kind) == [.started, .interrupted], "Interruption must not look completed")
        try append(event("task_complete", "turn-no-error-field", at: clock), to: file)
        try expect(reader.poll().events.map(\.kind) == [.completed], "Missing error field is a successful complete")

        var oversized = Data(repeating: 120, count: 1_100_000); oversized.append(10)
        oversized.append(try event("task_complete", "turn-after-large-line", at: clock))
        try append(oversized, to: file)
        try expect(reader.poll().events.map(\.turnID) == ["turn-after-large-line"], "Oversized line must be bounded/discarded without losing the next line")

        let subagent = sessions.appendingPathComponent("rollout-subagent.jsonl")
        var sub = try metadata("thread-child", source: ["subagent": ["thread_spawn": ["depth": 1]]], threadSource: "subagent")
        sub.append(try event("task_complete", "child-turn", at: clock)); try sub.write(to: subagent)
        let automation = sessions.appendingPathComponent("rollout-automation.jsonl")
        var automated = try metadata("thread-automation", threadSource: "automation")
        automated.append(try event("task_complete", "automated-turn", at: clock)); try automated.write(to: automation)
        let added = sessions.appendingPathComponent("rollout-new.jsonl")
        var addedData = try metadata("thread-new")
        addedData.append(try event("task_started", "new-turn", at: clock)); addedData.append(try event("task_complete", "new-turn", at: clock))
        try addedData.write(to: added)
        clock += 11
        result = reader.poll()
        try expect(result.events.map(\.kind) == [.started, .completed] && result.events.allSatisfy { $0.threadID == "thread-new" }, "Discover new user files and suppress subagent/automation")

        // A known background transcript must skip its entire history rather than parse it in 2 MiB batches.
        let largeChild = sessions.appendingPathComponent("rollout-large-child.jsonl")
        var childHistory = try metadata("thread-large-child", source: ["subagent": ["other": "guardian"]], threadSource: "subagent")
        childHistory.append(Data(repeating: 120, count: 3_000_000))
        childHistory.append(10)
        childHistory.append(try event("task_complete", "large-child-turn", at: clock))
        try childHistory.write(to: largeChild)
        try expect(reader.poll(forceScan: true).events.isEmpty, "Known non-user history must not emit any event")
        let archiveForSkip = cursors.appendingPathComponent("local-codex-cursors.json")
        let skipArchive = try JSONSerialization.jsonObject(with: Data(contentsOf: archiveForSkip)) as! [String: Any]
        let skipCursors = skipArchive["cursors"] as! [String: [String: Any]]
        let skippedCursor = skipCursors.first { URL(fileURLWithPath: $0.key).lastPathComponent == largeChild.lastPathComponent }?.value
        let skippedOffset = (skippedCursor?["offset"] as? NSNumber)?.intValue
        try expect(skippedOffset == childHistory.count, "Known non-user transcript must advance directly to EOF: actual \(String(describing: skippedOffset)), expected \(childHistory.count)")

        // A partial first session_meta must be reidentified; it cannot be permanently excluded as unknown.
        let partialHeaderFile = sessions.appendingPathComponent("rollout-partial-header.jsonl")
        let header = try metadata("thread-header")
        try header.prefix(header.count / 2).write(to: partialHeaderFile)
        let headerReader = CodexRolloutReader(rootURL: sessions, cursorDirectory: nil, now: { clock })
        _ = headerReader.begin()
        try append(header.suffix(header.count - header.count / 2), to: partialHeaderFile)
        try append(event("task_complete", "header-recovered", at: clock), to: partialHeaderFile)
        try expect(headerReader.poll().events.map(\.turnID) == ["header-recovered"], "A session with a completed partial header must recover its user identity")

        let deletedActiveFile = sessions.appendingPathComponent("rollout-deleted-active.jsonl")
        var deletedActive = try metadata("thread-deleted")
        deletedActive.append(try event("task_started", "deleted-turn", at: clock))
        try deletedActive.write(to: deletedActiveFile)
        result = reader.poll(forceScan: true)
        try expect(result.events.contains { $0.turnID == "deleted-turn" && $0.kind == .started } && result.activeCount == 1, "A freshly discovered start should be active before deletion")
        try fm.removeItem(at: deletedActiveFile)
        result = reader.poll()
        try expect(result.activeCount == 0 && result.events.isEmpty, "Deleting the active transcript clears stale activity without fabricating completion")

        // Deterministic archive encoding allows idle polling to avoid any persistent writes.
        let idleArchive = cursors.appendingPathComponent("local-codex-cursors.json")
        let knownModificationDate = Date(timeIntervalSince1970: 1_600_000_000)
        try fm.setAttributes([.modificationDate: knownModificationDate], ofItemAtPath: idleArchive.path)
        _ = reader.poll()
        let afterIdle = try fm.attributesOfItem(atPath: idleArchive.path)[.modificationDate] as? Date
        try expect(afterIdle == knownModificationDate, "An unchanged idle poll must not rewrite the archive")

        // Rename/dropout preserves live cursors, then catches only genuinely new lifecycle records on reconnect.
        let disconnected = fixture.appendingPathComponent("sessions-offline")
        try fm.moveItem(at: sessions, to: disconnected)
        try expect(!reader.poll().connected, "Missing root must report disconnected")
        try fm.moveItem(at: disconnected, to: sessions)
        try append(event("task_complete", "after-reconnect", at: clock), to: file)
        try expect(reader.poll().events.map(\.turnID) == ["after-reconnect"], "Reconnect must preserve cursor and deliver the new completion")

        // Same-path replacement and truncation must clear partial buffers, preserve deduplication and read new identity.
        let replacement = fixture.appendingPathComponent("replacement.jsonl")
        var replacementData = try metadata("thread-one")
        replacementData.append(try event("task_complete", "turn-one", at: clock))
        replacementData.append(try event("task_complete", "replacement-turn", at: clock))
        try replacementData.write(to: replacement)
        try fm.removeItem(at: file); try fm.moveItem(at: replacement, to: file)
        try expect(reader.poll().events.map(\.turnID) == ["replacement-turn"], "New inode must not replay previously delivered turns")
        var truncated = try metadata("thread-one")
        truncated.append(try event("task_complete", "tiny", at: clock)); try truncated.write(to: file)
        try expect(reader.poll().events.map(\.turnID) == ["tiny"], "A smaller file must reset its byte cursor safely")

        let archive = cursors.appendingPathComponent("local-codex-cursors.json")
        try expect(!String(decoding: Data(contentsOf: archive), as: UTF8.self).contains("PRIVATE-FIXTURE-TEXT"), "No prompt, message or error body may persist")
        let restarted = CodexRolloutReader(rootURL: sessions, cursorDirectory: cursors, now: { clock })
        try expect(restarted.begin().events.isEmpty, "Restart is a fresh EOF baseline, never a historical completion replay")
        try append(event("task_complete", "tiny", at: clock), to: file)
        try expect(restarted.poll().events.isEmpty, "Persisted terminal IDs suppress same-turn duplication after restart")
        try append(event("task_complete", "post-restart", at: clock), to: file)
        try expect(restarted.poll().events.map(\.turnID) == ["post-restart"], "New completion after restart must still work")

        let partialBaselineFile = sessions.appendingPathComponent("rollout-incomplete.jsonl")
        var partialBaseline = try metadata("thread-incomplete")
        let historicalPartial = try event("task_complete", "incomplete-old", at: clock)
        partialBaseline.append(historicalPartial.prefix(historicalPartial.count / 2)); try partialBaseline.write(to: partialBaselineFile)
        let partialReader = CodexRolloutReader(rootURL: sessions, cursorDirectory: nil, now: { clock })
        _ = partialReader.begin()
        try append(historicalPartial.suffix(historicalPartial.count - historicalPartial.count / 2), to: partialBaselineFile)
        try append(event("task_complete", "incomplete-new", at: clock), to: partialBaselineFile)
        try expect(partialReader.poll().events.map(\.turnID) == ["incomplete-new"], "Do not replay a historical partial line completed after startup")

        // Public monitor stop generations reject the reader callback even when it was already queued.
        let monitor = AgentTaskMonitor(rootURL: sessions, cursorDirectory: nil, now: { clock })
        monitor.start(); monitor.stop()
        try await Task.sleep(nanoseconds: 150_000_000)
        try expect(!monitor.isListening && monitor.activeTaskCount == 0 && monitor.lastEvent == nil, "Stopped generation must never write back")
        monitor.start()
        try await Task.sleep(nanoseconds: 200_000_000)
        try expect(monitor.isListening && monitor.lastEvent == nil, "Starting again establishes a clean baseline")
        monitor.stop()
        try testProgress(in: fixture, at: clock)
        print("PASS: local Codex metadata parsing, start/complete/error/interrupt, partial/oversized lines, discovery/filtering, background EOF skip, partial-header recovery, deleted activity, idle write suppression, reconnect, inode/truncation, durable dedupe, restart baseline, privacy and stop generations")
    }

    static func testProgress(in fixture: URL, at date: Date) throws {
        let fm = FileManager.default
        let home = fixture.appendingPathComponent("progress-codex")
        let sessions = home.appendingPathComponent("sessions")
        let archive = home.appendingPathComponent("cursors")
        try fm.createDirectory(at: sessions, withIntermediateDirectories: true)
        let index = home.appendingPathComponent("session_index.jsonl")
        var names = try jsonLine(["id": "progress-A", "thread_name": "标题元数据 A", "updated_at": "2026-10-15", "prompt": "PRIVATE-INDEX-CONTENT"])
        names.append(try jsonLine(["id": "progress-B", "thread_name": "标题元数据 B", "updated_at": "2026-10-15"]))
        try names.write(to: index)
        let a = sessions.appendingPathComponent("a.jsonl"), b = sessions.appendingPathComponent("b.jsonl")
        let reader = CodexRolloutReader(rootURL: sessions, cursorDirectory: archive, now: { date })
        try expect(reader.begin().activeTasks.isEmpty, "An empty baseline has no work progress")
        var aData = try metadata("progress-A"); aData.append(try event("task_started", "turn-A", at: date))
        var bData = try metadata("progress-B"); bData.append(try event("task_started", "turn-B", at: date))
        try aData.write(to: a); try bData.write(to: b)
        var result = reader.poll(forceScan: true)
        try expect(result.activeCount == 2 && result.activeTasks.map(\.threadID) == ["progress-A", "progress-B"], "Concurrent tasks need stable ordering")
        try expect(result.activeTasks.map(\.title) == ["标题元数据 A", "标题元数据 B"], "Titles must come from index metadata")
        try expect(result.activeTasks.allSatisfy { $0.phase == .thinking && $0.completedPlanSteps == nil && $0.totalPlanSteps == nil }, "No plan means no invented percentage or plan count")
        try append(toolRecord("custom_tool_call", callID: "call-A", at: date), to: a)
        result = reader.poll()
        try expect(result.events.isEmpty && result.activeTasks.first?.phase == .executing && result.activeTasks.last?.phase == .thinking, "A pending tool updates only its own task without a lifecycle notification")
        try append(toolRecord("custom_tool_call_output", callID: "call-A", at: date), to: a)
        try expect(reader.poll().activeTasks.first?.phase == .thinking, "Matched output must stop claiming its tool is running")
        try append(toolRecord("custom_tool_call", callID: "oversized-call", at: date), to: a)
        try expect(reader.poll().activeTasks.first?.phase == .executing, "A real pending tool is initially executing")
        let oversizedOutput = try jsonLine(["type": "response_item", "timestamp": ISO8601DateFormatter().string(from: date), "payload": ["type": "custom_tool_call_output", "call_id": "oversized-call", "output": String(repeating: "PRIVATE-OVERSIZED-CONTENT", count: 50_000)]])
        let afterOversized = try jsonLine(["type": "response_item", "timestamp": ISO8601DateFormatter().string(from: date), "payload": ["type": "reasoning", "summary": "PRIVATE-REASONING-CONTENT"]])
        try append(oversizedOutput, to: a); try append(afterOversized, to: a)
        result = reader.poll()
        try expect(result.activeCount == 2 && result.events.isEmpty && result.activeTasks.first?.phase == .thinking, "Skipping an oversized tool output must downgrade stale tool state without completing the task")
        try append(toolRecord("custom_tool_call", callID: "after-gap", at: date), to: a)
        try expect(reader.poll().activeTasks.first?.phase == .executing, "A known new call after a gap can restore a tool phase")
        try append(toolRecord("custom_tool_call_output", callID: "after-gap", at: date), to: a)
        _ = reader.poll()
        try append(jsonLine(["type": "event_msg", "timestamp": ISO8601DateFormatter().string(from: date), "payload": ["type": "item_completed", "turn_id": "turn-A", "item": ["type": "FileChange", "id": "past-file-change", "changes": "PRIVATE-CHANGE-CONTENT"]]]), to: a)
        try expect(reader.poll().activeTasks.first?.phase == .thinking, "A completed file-change item is not proof of current editing")
        try append(toolRecord("function_call", name: "request_user_input_async", callID: "async-question", at: date), to: a)
        try expect(reader.poll().activeTasks.first?.phase != .waiting, "An asynchronous question must not imply the model is paused waiting")
        try append(toolRecord("function_call_output", callID: "async-question", at: date), to: a)
        _ = reader.poll()

        let planInput = String(decoding: try JSONSerialization.data(withJSONObject: ["explanation": "PRIVATE-PLAN-CONTENT", "plan": [["step": "PRIVATE-PLAN-CONTENT", "status": "completed"], ["step": "PRIVATE-PLAN-CONTENT", "status": "in_progress"], ["step": "PRIVATE-PLAN-CONTENT", "status": "pending"]]]), as: UTF8.self)
        try append(toolRecord("function_call", name: "update_plan", callID: "plan-A", at: date, arguments: planInput), to: a)
        result = reader.poll()
        try expect(result.activeTasks.first?.completedPlanSteps == 1 && result.activeTasks.first?.totalPlanSteps == 3 && result.activeTasks.first?.phase == .planning, "Documented update_plan arguments provide plan-step counts only")
        try append(toolRecord("function_call_output", callID: "plan-A", at: date), to: a)
        result = reader.poll()
        try expect(result.activeTasks.first?.phase == .thinking && result.activeTasks.first?.totalPlanSteps == 3, "Tool completion preserves plan counts while restoring generic processing")
        let directPlan: [String: Any] = ["type": "plan_update", "turn_id": "turn-A", "plan": [["step": "PRIVATE-PLAN-CONTENT", "status": "completed"], ["step": "PRIVATE-PLAN-CONTENT", "status": "inProgress"]]]
        try append(jsonLine(["type": "event_msg", "timestamp": ISO8601DateFormatter().string(from: date), "payload": directPlan]), to: a)
        try expect(reader.poll().activeTasks.first?.totalPlanSteps == 2, "Protocol-compatible inProgress counts are accepted without retaining descriptions")
        let badPlan = "{\"plan\":[{\"step\":\"PRIVATE-PLAN-CONTENT\",\"status\":\"unknown\"}]}"
        try append(toolRecord("function_call", name: "update_plan", callID: "bad-plan", at: date, arguments: badPlan), to: a)
        try expect(reader.poll().activeTasks.first?.totalPlanSteps == 2, "Malformed/unsupported plans must not replace a known count")
        try append(toolRecord("function_call_output", callID: "bad-plan", at: date), to: a)
        _ = reader.poll()
        try append(toolRecord("function_call", name: "apply_patch", callID: "editing-B", at: date, turnID: "wrong-turn"), to: b)
        try expect(reader.poll().activeTasks.last?.phase == .thinking, "A stale turn cannot modify the active turn's progress")

        let saved = try String(contentsOf: archive.appendingPathComponent("local-codex-cursors.json"), encoding: .utf8)
        try expect(!saved.contains("PRIVATE-") && !saved.contains("标题元数据") && !saved.contains("completedPlanSteps"), "Only cursor/ID metadata may persist, not titles, tools, messages or plan descriptions")
        try append(event("task_complete", "turn-A", at: date), to: a)
        result = reader.poll()
        try expect(result.activeTasks.map(\.threadID) == ["progress-B"] && result.events.map(\.kind) == [.completed], "Completing one task leaves the concurrent task visible")
        try append(event("turn_aborted", "turn-B", at: date), to: b)
        try expect(reader.poll().activeTasks.isEmpty, "Interrupting the last task clears its progress bubble")

        // Restore a long running turn only with an actual task_started inside the bounded window.
        let longRoot = fixture.appendingPathComponent("long-codex/sessions")
        try fm.createDirectory(at: longRoot, withIntermediateDirectories: true)
        let longFile = longRoot.appendingPathComponent("long.jsonl")
        var longData = try metadata("long-task")
        longData.append(try event("task_started", "long-turn", at: date.addingTimeInterval(-600)))
        for _ in 0..<50 {
            longData.append(try jsonLine(["type": "response_item", "timestamp": ISO8601DateFormatter().string(from: date), "payload": ["type": "reasoning", "summary": String(repeating: "PRIVATE-LONG-CONTENT", count: 300)]]))
        }
        longData.append(try toolRecord("custom_tool_call", callID: "long-call", at: date))
        try longData.write(to: longFile)
        let noStartFile = longRoot.appendingPathComponent("unknown.jsonl")
        var noStart = try metadata("unknown-task")
        noStart.append(try toolRecord("custom_tool_call", callID: "unknown-call", at: date, turnID: "unknown-turn"))
        try noStart.write(to: noStartFile)
        let endedFile = longRoot.appendingPathComponent("ended.jsonl")
        var ended = try metadata("ended-task")
        ended.append(try event("task_started", "ended-turn", at: date.addingTimeInterval(-20)))
        ended.append(try event("task_complete", "ended-turn", at: date))
        try ended.write(to: endedFile)
        let staleFile = longRoot.appendingPathComponent("stale.jsonl")
        var stale = try metadata("stale-task")
        stale.append(try event("task_started", "stale-turn", at: date.addingTimeInterval(-120)))
        try stale.write(to: staleFile)
        let recovered = CodexRolloutReader(rootURL: longRoot, cursorDirectory: nil, now: { date }).begin()
        try expect(recovered.events.isEmpty && recovered.activeTasks.map(\.threadID) == ["long-task"], "Bounded baseline may restore a fresh long task, never historical completion or unanchored/stale activity")
        try expect(recovered.activeTasks.first?.startedAt == date.addingTimeInterval(-600) && recovered.activeTasks.first?.phase == .executing, "Recovered work retains its real start and a known outstanding tool")
        try expect(recovered.activeTasks.first?.title == "任务 · g-task", "Missing index falls back to a short identity, never message content")
        let longOversizedOutput = try jsonLine(["type": "response_item", "timestamp": ISO8601DateFormatter().string(from: date), "payload": ["type": "custom_tool_call_output", "call_id": "long-call", "output": String(repeating: "PRIVATE-OVERSIZED-CONTENT", count: 50_000)]])
        try append(longOversizedOutput, to: longFile); try append(afterOversized, to: longFile)
        let gapReader = CodexRolloutReader(rootURL: longRoot, cursorDirectory: nil, now: { date })
        let recoveredGap = gapReader.begin()
        try expect(recoveredGap.events.isEmpty && recoveredGap.activeCount == 1 && recoveredGap.activeTasks.first?.phase == .thinking, "A skipped output in baseline must not leave a stale pending tool or invent completion")
        try append(toolRecord("custom_tool_call", callID: "long-after-gap", at: date), to: longFile)
        try expect(gapReader.poll().activeTasks.first?.phase == .executing, "Baseline gap recovery still permits subsequent explicit call progress")
        print("PASS: concurrent task metadata, index titles, paired tool stages, oversized-output gap downgrade in incremental/baseline reads, no false waiting/current-stage inference, plan-step-only counts, progress privacy, per-turn cleanup and bounded long-task baseline")
    }
}
