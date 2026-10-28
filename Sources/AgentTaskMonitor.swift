import Combine
import Foundation

enum AgentTaskEventKind: String, Codable, Sendable {
    case started, completed, interrupted, failed
}

/// Metadata only. Prompts, assistant replies, tool input and transcript contents never leave the reader.
struct AgentTaskEvent: Identifiable, Equatable, Codable, Sendable {
    let threadID: String
    let turnID: String
    let kind: AgentTaskEventKind
    let occurredAt: Date
    var id: String { "\(threadID)|\(turnID)|\(kind.rawValue)" }
}

enum AgentTaskPhase: String, Codable, Sendable {
    case thinking, planning, executing, editing, searching, waiting, reviewing
    var label: String {
        switch self {
        case .thinking: return "处理中"
        case .planning: return "更新计划"
        case .executing: return "执行工具"
        case .editing: return "修改文件"
        case .searching: return "检索资料"
        case .waiting: return "等待输入"
        case .reviewing: return "整理结果"
        }
    }
}

struct AgentActiveTask: Identifiable, Equatable, Sendable {
    let threadID: String
    let turnID: String
    var title: String
    let startedAt: Date
    var updatedAt: Date
    var phase: AgentTaskPhase
    var completedPlanSteps: Int?
    var totalPlanSteps: Int?
    var id: String { "\(threadID)|\(turnID)" }
}

/// Only step statuses are decoded; descriptions/explanations never enter retained state.
private struct CodexPlanCounts: Decodable {
    let completed: Int
    let total: Int
    private struct Step: Decodable { let status: String }
    private enum CodingKeys: String, CodingKey { case plan }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let steps = try c.decode([Step].self, forKey: .plan)
        guard !steps.isEmpty, steps.count <= 200,
              steps.allSatisfy({ ["pending", "in_progress", "inProgress", "completed"].contains($0.status) }) else {
            throw DecodingError.dataCorruptedError(forKey: .plan, in: c, debugDescription: "Unsupported plan status list")
        }
        completed = steps.filter { $0.status == "completed" }.count
        total = steps.count
    }
}

private struct CodexLifecycleRecord: Decodable {
    let type: String
    let timestamp: String?
    let payload: Payload
    struct Payload: Decodable {
        let type: String?
        let id: String?
        let turnID: String?
        let source: Source?
        let threadSource: String?
        let startedAt: Double?
        let completedAt: Double?
        let hasError: Bool
        let name: String?
        let callID: String?
        let item: Item?
        let plan: CodexPlanCounts?
        struct Item: Decodable { let type: String?; let id: String? }
        enum CodingKeys: String, CodingKey {
            case type, id, source, error, name, item, arguments, input
            case callID = "call_id"
            case turnID = "turn_id", threadSource = "thread_source"
            case startedAt = "started_at", completedAt = "completed_at"
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try? c.decode(String.self, forKey: .type)
            id = try? c.decode(String.self, forKey: .id)
            turnID = try? c.decode(String.self, forKey: .turnID)
            source = try? c.decode(Source.self, forKey: .source)
            threadSource = try? c.decode(String.self, forKey: .threadSource)
            startedAt = try? c.decode(Double.self, forKey: .startedAt)
            completedAt = try? c.decode(Double.self, forKey: .completedAt)
            hasError = c.contains(.error) && (try? c.decodeNil(forKey: .error)) != true
            name = try? c.decode(String.self, forKey: .name)
            callID = try? c.decode(String.self, forKey: .callID)
            item = try? c.decode(Item.self, forKey: .item)
            if type == "plan_update" {
                plan = try? CodexPlanCounts(from: decoder)
            } else if (type == "function_call" || type == "custom_tool_call"),
                      name == "update_plan" || name == "functions.update_plan" {
                // This tool's documented argument shape is the only tool input we inspect.
                // Decode statuses only and immediately discard the original serialized arguments.
                let key: CodingKeys = type == "function_call" ? .arguments : .input
                if let text = try? c.decode(String.self, forKey: key), text.utf8.count <= 65_536 {
                    plan = try? JSONDecoder().decode(CodexPlanCounts.self, from: Data(text.utf8))
                } else { plan = nil }
            } else { plan = nil }
        }
    }
    enum Source: Decodable {
        case user(String), other
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let value = try? c.decode(String.self), !value.lowercased().contains("subagent") {
                self = .user(value)
            } else { self = .other }
        }
        var permitsUserTask: Bool {
            if case .user(let value) = self { return ["vscode", "cli", "exec", "app-server", "desktop"].contains(value) }
            return false
        }
    }
}

private struct CodexFileCursor: Codable {
    var offset: UInt64
    var inode: UInt64
    var device: UInt64
    var threadID: String?
    var eligible: Bool
}

private struct CodexCursorArchive: Codable {
    var version = 1
    var cursors: [String: CodexFileCursor]
    var seen: [String]
}

struct CodexMonitorSnapshot: Sendable {
    let connected: Bool
    let status: String
    let activeCount: Int
    let events: [AgentTaskEvent]
    var activeTasks: [AgentActiveTask] = []
}

/// This reads the current local Codex rollout format, not a cloud API. It never writes inside CODEX_HOME.
/// Mutable state is confined to the sampler queue (or a single test thread).
final class CodexRolloutReader: @unchecked Sendable {
    private let rootURL: URL
    private let cursorURL: URL?
    private let now: () -> Date
    private let fm = FileManager.default
    private var cursors: [String: CodexFileCursor] = [:]
    private var pending: [String: Data] = [:]
    private var droppingLine: Set<String> = []
    private var seen: Set<String> = []
    private var seenOrder: [String] = []
    private var terminalTurns: Set<String> = []
    private var active: [String: AgentActiveTask] = [:]
    private var outstandingCalls: [String: [String: AgentTaskPhase]] = [:]
    private var titles: [String: String] = [:]
    private var listeningSince: Date?
    private var lastScan = Date.distantPast
    private let decoder = JSONDecoder()
    private let dateParser = ISO8601DateFormatter()
    private let fractionalDateParser = ISO8601DateFormatter()
    private let maxLineBytes = 1_048_576
    private let maxReadPerFile = 2_097_152
    private let tailBytes: UInt64 = 131_072
    private let seenLimit = 4096
    private var lastSavedArchive: Data?

    init(rootURL: URL, cursorDirectory: URL?, now: @escaping () -> Date = Date.init) {
        self.rootURL = rootURL.standardizedFileURL
        self.cursorURL = cursorDirectory?.appendingPathComponent("local-codex-cursors.json")
        self.now = now
        fractionalDateParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let cursorURL, let data = try? Data(contentsOf: cursorURL), data.count <= 2_097_152,
           let saved = try? JSONDecoder().decode(CodexCursorArchive.self, from: data), saved.version == 1 {
            // A restart always baselines offsets again. Seen metadata still prevents replay after replacement.
            seenOrder = Array(saved.seen.suffix(seenLimit))
            seen = Set(seenOrder)
            rebuildTerminalTurns()
            lastSavedArchive = data
        }
    }

    func begin() -> CodexMonitorSnapshot {
        cursors.removeAll(); pending.removeAll(); droppingLine.removeAll(); active.removeAll()
        outstandingCalls.removeAll()
        listeningSince = now()
        lastScan = .distantPast
        return poll(baseline: true, forceScan: true)
    }

    func poll(baseline: Bool = false, forceScan: Bool = false) -> CodexMonitorSnapshot {
        guard let listeningSince else { return CodexMonitorSnapshot(connected: false, status: "未连接本机 Codex", activeCount: 0, events: []) }
        var directory: ObjCBool = false
        guard fm.fileExists(atPath: rootURL.path, isDirectory: &directory), directory.boolValue,
              fm.isReadableFile(atPath: rootURL.path) else {
            return CodexMonitorSnapshot(connected: false, status: "等待本机 Codex 记录", activeCount: 0, events: [])
        }
        var events: [AgentTaskEvent] = []
        if baseline || forceScan || now().timeIntervalSince(lastScan) >= 10 {
            lastScan = now()
            refreshTitles()
            if let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
                for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                    guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                          values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                    let path = url.path
                    guard cursors[path] == nil, let attributes = attributes(url) else { continue }
                    var cursor = CodexFileCursor(offset: 0, inode: attributes.inode, device: attributes.device, threadID: nil, eligible: false)
                    identify(url, cursor: &cursor)
                    if baseline {
                        establishActiveBaseline(url, size: attributes.size, cursor: cursor)
                        cursor.offset = attributes.size
                        // An incomplete existing line belongs to history; discard its remainder on append.
                        if attributes.size > 0, !endsWithNewline(url, size: attributes.size) { droppingLine.insert(path) }
                    }
                    cursors[path] = cursor
                }
            }
        }
        if !baseline {
            for path in cursors.keys.sorted() {
                guard var cursor = cursors[path] else { continue }
                let url = URL(fileURLWithPath: path)
                guard let attrs = attributes(url) else {
                    if definitelyMissing(url), let threadID = cursor.threadID {
                        removeActive(threadID)
                        pending.removeValue(forKey: path); droppingLine.remove(path)
                    }
                    continue
                }
                if attrs.inode != cursor.inode || attrs.device != cursor.device || attrs.size < cursor.offset {
                    if let threadID = cursor.threadID { removeActive(threadID) }
                    cursor = CodexFileCursor(offset: 0, inode: attrs.inode, device: attrs.device, threadID: nil, eligible: false)
                    pending.removeValue(forKey: path); droppingLine.remove(path)
                    identify(url, cursor: &cursor)
                }
                // An initially partial session_meta can become complete after this cursor was created.
                if cursor.threadID == nil { identify(url, cursor: &cursor) }
                if cursor.threadID != nil && !cursor.eligible {
                    // Known background/subagent transcripts are not a source for user notifications.
                    // Skip their bodies entirely, including very large histories discovered while listening.
                    cursor.offset = attrs.size
                    pending.removeValue(forKey: path); droppingLine.remove(path)
                    cursors[path] = cursor
                    continue
                }
                if attrs.size > cursor.offset, let handle = try? FileHandle(forReadingFrom: url) {
                    defer { try? handle.close() }
                    do {
                        try handle.seek(toOffset: cursor.offset)
                        var budget = maxReadPerFile
                        while budget > 0, cursor.offset < attrs.size {
                            let count = min(65_536, budget, Int(min(attrs.size - cursor.offset, UInt64(Int.max))))
                            guard let data = try handle.read(upToCount: count), !data.isEmpty else { break }
                            cursor.offset += UInt64(data.count); budget -= data.count
                            consume(data, path: path, onOversized: {
                                if let threadID = cursor.threadID { downgradeProgress(threadID) }
                            }) { line in
                                guard let record = try? decoder.decode(CodexLifecycleRecord.self, from: line) else { return }
                                updateIdentity(record, cursor: &cursor)
                                if let event = lifecycle(record, cursor: cursor), event.occurredAt >= listeningSince.addingTimeInterval(-2) {
                                    if accept(event) { events.append(event) }
                                } else if cursor.eligible, let threadID = cursor.threadID {
                                    updateProgress(record, threadID: threadID)
                                }
                            }
                        }
                    } catch { /* Keep the last good cursor; a later poll retries without inventing a state. */ }
                }
                cursors[path] = cursor
            }
        }
        save()
        let tasks = active.values.sorted { $0.startedAt == $1.startedAt ? $0.id < $1.id : $0.startedAt < $1.startedAt }
        return CodexMonitorSnapshot(connected: true, status: cursors.isEmpty ? "已连接，等待本机任务" : "已连接本机 Codex", activeCount: tasks.count, events: events, activeTasks: tasks)
    }

    private func attributes(_ url: URL) -> (size: UInt64, inode: UInt64, device: UInt64)? {
        guard let a = try? fm.attributesOfItem(atPath: url.path), a[.type] as? FileAttributeType == .typeRegular,
              let size = a[.size] as? NSNumber, let inode = a[.systemFileNumber] as? NSNumber,
              let device = a[.systemNumber] as? NSNumber else { return nil }
        return (size.uint64Value, inode.uint64Value, device.uint64Value)
    }
    private func definitelyMissing(_ url: URL) -> Bool {
        do { _ = try fm.attributesOfItem(atPath: url.path); return false }
        catch let error as NSError {
            return (error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code))
                || (error.domain == NSPOSIXErrorDomain && error.code == 2)
        }
    }
    private func identify(_ url: URL, cursor: inout CodexFileCursor) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        var data = Data()
        while data.count <= maxLineBytes {
            guard let chunk = try? handle.read(upToCount: 16_384), !chunk.isEmpty else { break }
            if let end = chunk.firstIndex(of: 10) { data.append(chunk[..<end]); break }
            data.append(chunk)
        }
        guard data.count <= maxLineBytes, let record = try? decoder.decode(CodexLifecycleRecord.self, from: data) else { return }
        updateIdentity(record, cursor: &cursor)
    }
    private func updateIdentity(_ record: CodexLifecycleRecord, cursor: inout CodexFileCursor) {
        guard record.type == "session_meta" else { return }
        let p = record.payload
        cursor.threadID = safeID(p.id)
        cursor.eligible = cursor.threadID != nil && p.source?.permitsUserTask == true && (p.threadSource == nil || p.threadSource == "user")
    }
    private func safeID(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.utf8.count <= 128,
              value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        return value
    }
    private func lifecycle(_ record: CodexLifecycleRecord, cursor: CodexFileCursor) -> AgentTaskEvent? {
        guard cursor.eligible, record.type == "event_msg", let threadID = cursor.threadID,
              let turnID = safeID(record.payload.turnID) else { return nil }
        let kind: AgentTaskEventKind
        switch record.payload.type {
        case "task_started": kind = .started
        case "task_complete": kind = record.payload.hasError ? .failed : .completed
        case "turn_aborted": kind = .interrupted
        default: return nil
        }
        let seconds = kind == .started ? record.payload.startedAt : record.payload.completedAt
        let date = seconds.flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0) : nil } ?? parsedDate(record.timestamp)
        guard let date, date <= now().addingTimeInterval(60) else { return nil }
        return AgentTaskEvent(threadID: threadID, turnID: turnID, kind: kind, occurredAt: date)
    }
    private func parsedDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return fractionalDateParser.date(from: value) ?? dateParser.date(from: value)
    }
    private func accept(_ event: AgentTaskEvent) -> Bool {
        let turnKey = "\(event.threadID)|\(event.turnID)"
        guard !seen.contains(event.id), !terminalTurns.contains(turnKey) else { return false }
        seen.insert(event.id); seenOrder.append(event.id)
        if event.kind == .started {
            removeActive(event.threadID)
            active[event.threadID] = task(for: event)
        }
        else {
            terminalTurns.insert(turnKey)
            if active[event.threadID]?.turnID == event.turnID { removeActive(event.threadID) }
        }
        if seenOrder.count > seenLimit {
            seenOrder.removeFirst(seenOrder.count - seenLimit)
            seen = Set(seenOrder); rebuildTerminalTurns()
        }
        return true
    }
    private func task(for event: AgentTaskEvent) -> AgentActiveTask {
        AgentActiveTask(threadID: event.threadID, turnID: event.turnID,
                        title: titles[event.threadID] ?? "任务 · \(event.threadID.suffix(6))",
                        startedAt: event.occurredAt, updatedAt: event.occurredAt, phase: .thinking,
                        completedPlanSteps: nil, totalPlanSteps: nil)
    }
    private func removeActive(_ threadID: String) {
        if let previous = active.removeValue(forKey: threadID) { outstandingCalls.removeValue(forKey: previous.id) }
    }
    private func downgradeProgress(_ threadID: String) {
        guard var task = active[threadID] else { return }
        // A skipped record could be a tool result. Retain the lifecycle but stop claiming that tool is open.
        outstandingCalls.removeValue(forKey: task.id)
        task.phase = .thinking
        active[threadID] = task
    }
    private func updateProgress(_ record: CodexLifecycleRecord, threadID: String) {
        guard var task = active[threadID],
              record.payload.turnID == nil || record.payload.turnID == task.turnID,
              let date = parsedDate(record.timestamp), date >= task.updatedAt, date <= now().addingTimeInterval(60) else { return }
        let p = record.payload
        var calls = outstandingCalls[task.id] ?? [:]
        let callID = p.callID.flatMap { !$0.isEmpty && $0.utf8.count <= 256 ? $0 : nil }
        var isProgress = false
        if record.type == "response_item" {
            switch p.type {
            case "function_call", "custom_tool_call":
                if let callID, calls.count < 64 {
                    let phase = toolPhase(p.name)
                    calls[callID] = phase; task.phase = phase
                    isProgress = true
                }
            case "function_call_output", "custom_tool_call_output":
                if let callID, calls.removeValue(forKey: callID) != nil {
                    task.phase = calls.isEmpty ? .thinking : .executing
                    isProgress = true
                }
            case "reasoning", "message":
                // Do not interpret text or reasoning bodies. These records only refresh recent activity.
                if calls.isEmpty { task.phase = .thinking }
                isProgress = true
            default: break
            }
        } else if record.type == "event_msg", p.type == "item_completed" {
            // A completed item describes the past, never proof that the same action is still running.
            if let id = p.item?.id { calls.removeValue(forKey: id) }
            if calls.isEmpty { task.phase = .thinking }
            isProgress = true
        }
        if let plan = p.plan {
            task.completedPlanSteps = plan.completed; task.totalPlanSteps = plan.total
            isProgress = true
        }
        guard isProgress else { return }
        task.updatedAt = date
        outstandingCalls[task.id] = calls
        active[threadID] = task
    }
    private func toolPhase(_ name: String?) -> AgentTaskPhase {
        switch name {
        case "update_plan", "functions.update_plan": return .planning
        case "apply_patch", "functions.apply_patch": return .editing
        case "web_search", "search_query", "web.run", "web__run": return .searching
        default: return .executing
        }
    }
    private func refreshTitles() {
        struct Entry: Decodable { let id: String; let thread_name: String }
        let index = rootURL.deletingLastPathComponent().appendingPathComponent("session_index.jsonl")
        guard let attributes = attributes(index), let h = try? FileHandle(forReadingFrom: index) else { return }
        defer { try? h.close() }
        let limit: UInt64 = 4_194_304
        let offset = attributes.size > limit ? attributes.size - limit : 0
        do {
            try h.seek(toOffset: offset)
            guard let data = try h.read(upToCount: Int(limit)) else { return }
            for (i, line) in data.split(separator: 10).enumerated() where !(offset > 0 && i == 0) && line.count <= 16_384 {
                guard let entry = try? decoder.decode(Entry.self, from: Data(line)), let id = safeID(entry.id) else { continue }
                let sanitized = entry.thread_name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
                let title = String(String.UnicodeScalarView(sanitized)).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                if !title.isEmpty { titles[id] = String(title.prefix(64)) }
            }
            for id in active.keys {
                if let title = titles[id] { active[id]?.title = title }
            }
        } catch { }
    }
    private func rebuildTerminalTurns() {
        terminalTurns = Set(seenOrder.compactMap { id in
            let pieces = id.split(separator: "|")
            guard pieces.count == 3, pieces[2] != "started" else { return nil }
            return pieces.prefix(2).joined(separator: "|")
        })
    }
    private func consume(_ data: Data, path: String, onOversized: () -> Void, line: (Data) -> Void) {
        var buffer = pending[path] ?? Data()
        var dropping = droppingLine.contains(path)
        var start = data.startIndex
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: 10) ?? data.endIndex
            let segment = data[start..<end]
            if !dropping {
                if buffer.count + segment.count > maxLineBytes {
                    buffer.removeAll(keepingCapacity: false); dropping = true
                    onOversized()
                }
                else { buffer.append(segment) }
            }
            if end < data.endIndex {
                if !dropping, !buffer.isEmpty { line(buffer) }
                buffer.removeAll(keepingCapacity: false); dropping = false
                start = data.index(after: end)
            } else { break }
        }
        pending[path] = buffer
        if dropping { droppingLine.insert(path) } else { droppingLine.remove(path) }
    }
    private func endsWithNewline(_ url: URL, size: UInt64) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        do { try h.seek(toOffset: size - 1); return try h.read(upToCount: 1)?.first == 10 } catch { return false }
    }
    private func establishActiveBaseline(_ url: URL, size: UInt64, cursor: CodexFileCursor) {
        guard cursor.eligible, let h = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? h.close() }
        do {
            func records(in bound: UInt64) throws -> [CodexLifecycleRecord?] {
                let offset = size > bound ? size - bound : 0
                try h.seek(toOffset: offset)
                guard let data = try h.read(upToCount: Int(bound)) else { return [] }
                let lines = data.split(separator: 10, omittingEmptySubsequences: false)
                var decoded: [CodexLifecycleRecord?] = []
                for (i, bytes) in lines.enumerated() {
                    guard !(offset > 0 && i == 0), !bytes.isEmpty,
                          // No trailing incomplete record is used as an activity signal.
                          i < lines.count - 1 else { continue }
                    if bytes.count > maxLineBytes { decoded.append(nil) }
                    else { decoded.append(try? decoder.decode(CodexLifecycleRecord.self, from: Data(bytes))) }
                }
                return decoded
            }
            var recent = try records(in: tailBytes)
            guard let latestTimestamp = recent.compactMap({ $0.flatMap { parsedDate($0.timestamp) } }).last,
                  now().timeIntervalSince(latestTimestamp) >= -60, now().timeIntervalSince(latestTimestamp) <= 30 else { return }
            // Expand only a fresh user transcript. An absent start in this bounded window stays unknown.
            if recent.compactMap({ $0.flatMap { lifecycle($0, cursor: cursor) } }).last == nil, size > tailBytes {
                recent = try records(in: 4_194_304)
            }
            guard let last = recent.compactMap({ $0.flatMap { lifecycle($0, cursor: cursor) } }).last,
                  last.kind == .started, !terminalTurns.contains("\(last.threadID)|\(last.turnID)") else { return }
            active[last.threadID] = task(for: last)
            for entry in recent {
                guard let record = entry else { downgradeProgress(last.threadID); continue }
                guard let date = parsedDate(record.timestamp), date >= last.occurredAt else { continue }
                updateProgress(record, threadID: last.threadID)
            }
        } catch { }
    }
    private func save() {
        guard let cursorURL else { return }
        // Paths, byte positions, identities and dedupe IDs only; no raw JSON lines are persisted.
        let entries = cursors.sorted(by: { $0.key < $1.key }).prefix(2048).map { ($0.key, $0.value) }
        let kept = Dictionary(uniqueKeysWithValues: entries)
        let archive = CodexCursorArchive(cursors: kept, seen: seenOrder)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(archive), data.count <= 2_097_152, data != lastSavedArchive else { return }
        try? fm.createDirectory(at: cursorURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try data.write(to: cursorURL, options: .atomic)
            lastSavedArchive = data
        } catch { }
    }
}

private final class CodexTaskSampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "XiaoKe.codex.events", qos: .utility)
    private let reader: CodexRolloutReader
    private let inbox: AgentInboxReader
    private var timer: DispatchSourceTimer?
    private var generation = 0
    init(reader: CodexRolloutReader, inbox: AgentInboxReader) { self.reader = reader; self.inbox = inbox }
    private func merged(_ codex: CodexMonitorSnapshot) -> CodexMonitorSnapshot {
        let external = inbox.poll()
        return CodexMonitorSnapshot(connected: true,
            status: "通用 Agent 接入已就绪 · " + codex.status,
            activeCount: codex.activeTasks.count + external.tasks.count,
            events: codex.events + external.events, activeTasks: codex.activeTasks + external.tasks)
    }
    func start(_ callback: @escaping @Sendable (CodexMonitorSnapshot) -> Void) {
        queue.async { [self] in
            generation += 1
            let expected = generation
            timer?.cancel()
            inbox.reset()
            _ = inbox.poll() // Baseline: retain live tasks, suppress pre-launch completion toasts.
            callback(merged(reader.begin()))
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 2, repeating: .seconds(2), leeway: .milliseconds(200))
            t.setEventHandler { [weak self] in
                guard let self, self.generation == expected else { return }
                callback(self.merged(self.reader.poll()))
            }
            timer = t; t.resume()
        }
    }
    func stop() {
        // Never wait for disk I/O on the UI thread. The owner's generation rejects queued callbacks.
        queue.async { [self] in generation += 1; timer?.setEventHandler {}; timer?.cancel(); timer = nil }
    }
}

@MainActor
final class AgentTaskMonitor: ObservableObject {
    @Published private(set) var connectionStatus = "尚未开启 Agent 接入"
    @Published private(set) var activeTaskCount = 0
    @Published private(set) var activeTasks: [AgentActiveTask] = []
    @Published private(set) var lastEvent: AgentTaskEvent?
    @Published private(set) var isListening = false
    private let sampler: CodexTaskSampler
    private var running = false
    private var generation = 0

    init(rootURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions"),
         cursorDirectory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("XiaoKeCompanion/codex-events"),
         now: @escaping () -> Date = Date.init) {
        let base = ProcessInfo.processInfo.environment["XIAOKE_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("XiaoKeCompanion")
        sampler = CodexTaskSampler(reader: CodexRolloutReader(rootURL: rootURL, cursorDirectory: cursorDirectory, now: now),
                                   inbox: AgentInboxReader(directory: base.appendingPathComponent("agent-inbox"), now: now))
    }
    func start() {
        guard !running else { return }
        running = true; generation += 1; lastEvent = nil
        connectionStatus = "正在连接 Agent"
        let expected = generation
        sampler.start { [weak self] snapshot in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.generation == expected else { return }
                self.connectionStatus = snapshot.status
                self.isListening = snapshot.connected
                self.activeTaskCount = snapshot.activeCount
                self.activeTasks = snapshot.activeTasks
                for event in snapshot.events { self.lastEvent = event }
            }
        }
    }
    func stop() {
        running = false; generation += 1; sampler.stop()
        isListening = false; activeTaskCount = 0; activeTasks = []; lastEvent = nil
        connectionStatus = "已暂停 Codex 提醒"
    }
}
