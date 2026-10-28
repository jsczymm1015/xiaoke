import Foundation

struct CodexTaskBubbleContent: Equatable {
    let taskID: String
    let title: String
    let phaseLabel: String
    let elapsedSeconds: Int
    let position: Int
    let taskCount: Int
    let completedPlanSteps: Int?
    let totalPlanSteps: Int?

    var elapsedLabel: String {
        if elapsedSeconds >= 3600 { return "\(elapsedSeconds / 3600)小时\(String(format: "%02d", elapsedSeconds / 60 % 60))分" }
        if elapsedSeconds >= 60 { return "\(elapsedSeconds / 60)分\(String(format: "%02d", elapsedSeconds % 60))秒" }
        return "\(elapsedSeconds)秒"
    }
    var indexLabel: String { "\(position)/\(taskCount)" }
    var planLabel: String? {
        guard let completed = completedPlanSteps, let total = totalPlanSteps,
              total > 0, completed >= 0, completed <= total else { return nil }
        return "计划步骤 \(completed)/\(total)"
    }
    /// This fraction is only for the observed plan steps, never overall task completion.
    var planFraction: Double? {
        guard planLabel != nil, let completed = completedPlanSteps, let total = totalPlanSteps else { return nil }
        return Double(completed) / Double(total)
    }
    var accessibilityValue: String {
        ["Agent：\(title)", phaseLabel, "已用\(elapsedLabel)", planLabel, "任务 \(indexLabel)"]
            .compactMap { $0 }.joined(separator: "；")
    }
}

enum CodexTaskBubbleDisplay: Equatable {
    case message(String)
    case task(CodexTaskBubbleContent)

    var accessibilityValue: String {
        switch self {
        case .message(let text): return text
        case .task(let content): return content.accessibilityValue
        }
    }
}

/// Pure, clock-injected presentation state. It does not read logs, run tasks, or award XP.
struct CodexTaskBubbleCycler {
    let rotationInterval: TimeInterval
    private(set) var tasks: [AgentActiveTask] = []
    private(set) var progressEnabled = false
    private(set) var progressVisible = true
    private var selectedID: String?
    private var nextRotationAt: Date?
    private var pausedAt: Date?
    private var transientText: String?
    private var transientUntil: Date?

    init(rotationInterval: TimeInterval = 4) {
        self.rotationInterval = rotationInterval.isFinite ? max(0.5, rotationInterval) : 4
    }

    mutating func setProgressEnabled(_ enabled: Bool, at now: Date) {
        guard enabled != progressEnabled else { return }
        progressEnabled = enabled
        if !enabled {
            tasks = []
            selectedID = nil
            nextRotationAt = nil
            pausedAt = nil
        }
        reconcilePause(at: now)
    }

    mutating func setProgressVisible(_ visible: Bool, at now: Date) {
        progressVisible = visible
        reconcilePause(at: now)
    }

    mutating func updateTasks(_ incoming: [AgentActiveTask], at now: Date) {
        guard progressEnabled else { return }
        var unique: [String: AgentActiveTask] = [:]
        for task in incoming {
            if let previous = unique[task.id], previous.updatedAt > task.updatedAt { continue }
            unique[task.id] = task
        }
        let sorted = unique.values.sorted {
            $0.startedAt == $1.startedAt ? $0.id < $1.id : $0.startedAt < $1.startedAt
        }
        let previousTasks = tasks
        let previousIndex = previousTasks.firstIndex { $0.id == selectedID }
        tasks = sorted
        guard !tasks.isEmpty else {
            selectedID = nil
            nextRotationAt = nil
            pausedAt = nil
            return
        }
        if !tasks.contains(where: { $0.id == selectedID }) {
            // Prefer the next surviving neighbour when the visible task finishes.
            var successor: String?
            if let previousIndex, !previousTasks.isEmpty {
                for distance in 1...previousTasks.count {
                    let id = previousTasks[(previousIndex + distance) % previousTasks.count].id
                    if tasks.contains(where: { $0.id == id }) { successor = id; break }
                }
            }
            selectedID = successor ?? tasks.first?.id
            nextRotationAt = now.addingTimeInterval(rotationInterval)
            pausedAt = shouldPause(at: now) ? now : nil
        } else if nextRotationAt == nil {
            nextRotationAt = now.addingTimeInterval(rotationInterval)
        }
        reconcilePause(at: now)
    }

    mutating func showMessage(_ text: String, seconds: TimeInterval = 7, at now: Date) {
        guard !text.isEmpty else { return }
        transientText = text
        transientUntil = now.addingTimeInterval(seconds.isFinite ? max(0, seconds) : 7)
        reconcilePause(at: now)
    }

    @discardableResult
    mutating func nextTask(at now: Date) -> Bool {
        guard case .task = display(at: now), !tasks.isEmpty else { return false }
        let index = tasks.firstIndex { $0.id == selectedID } ?? 0
        selectedID = tasks[(index + 1) % tasks.count].id
        nextRotationAt = now.addingTimeInterval(rotationInterval)
        return true
    }

    mutating func display(at now: Date) -> CodexTaskBubbleDisplay? {
        if let until = transientUntil, now >= until {
            transientText = nil
            transientUntil = nil
        }
        reconcilePause(at: now)
        if let transientText { return .message(transientText) }
        guard progressEnabled, progressVisible, !tasks.isEmpty else { return nil }
        if let nextRotationAt, now >= nextRotationAt {
            let hops = Int(floor(now.timeIntervalSince(nextRotationAt) / rotationInterval)) + 1
            let index = tasks.firstIndex { $0.id == selectedID } ?? 0
            selectedID = tasks[(index + hops % tasks.count) % tasks.count].id
            self.nextRotationAt = nextRotationAt.addingTimeInterval(Double(hops) * rotationInterval)
        }
        let index = tasks.firstIndex { $0.id == selectedID } ?? 0
        let task = tasks[index]
        let title = task.title.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return .task(CodexTaskBubbleContent(taskID: task.id, title: title.isEmpty ? "Agent 任务" : title,
            phaseLabel: task.phase.label, elapsedSeconds: max(0, Int(now.timeIntervalSince(task.startedAt))),
            position: index + 1, taskCount: tasks.count,
            completedPlanSteps: task.completedPlanSteps, totalPlanSteps: task.totalPlanSteps))
    }

    private func shouldPause(at now: Date) -> Bool {
        !progressVisible || (transientUntil.map { now < $0 } ?? false)
    }

    private mutating func reconcilePause(at now: Date) {
        guard progressEnabled, !tasks.isEmpty else { pausedAt = nil; return }
        if shouldPause(at: now) {
            if pausedAt == nil { pausedAt = now }
        } else if let pausedAt {
            if let nextRotationAt { self.nextRotationAt = nextRotationAt.addingTimeInterval(max(0, now.timeIntervalSince(pausedAt))) }
            self.pausedAt = nil
        }
    }
}
