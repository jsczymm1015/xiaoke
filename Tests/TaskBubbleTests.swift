import Foundation

@main
struct TaskBubbleTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        assertions += 1
        guard condition() else { throw NSError(domain: "TaskBubbleTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func main() throws {
        let start = Date(timeIntervalSince1970: 1_792_045_466)
        func time(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }
        func task(_ name: String, started: Double = 0, updated: Double = 0, phase: AgentTaskPhase = .thinking,
                  completed: Int? = nil, total: Int? = nil, title: String? = nil) -> AgentActiveTask {
            AgentActiveTask(threadID: name, turnID: "turn", title: title ?? "任务 \(name)", startedAt: time(started),
                updatedAt: time(updated), phase: phase, completedPlanSteps: completed, totalPlanSteps: total)
        }
        func enabled(_ tasks: [AgentActiveTask]) -> CodexTaskBubbleCycler {
            var cycler = CodexTaskBubbleCycler()
            cycler.setProgressEnabled(true, at: time(0))
            cycler.updateTasks(tasks, at: time(0))
            return cycler
        }
        func content(_ cycler: inout CodexTaskBubbleCycler, at seconds: Double) -> CodexTaskBubbleContent? {
            guard case .task(let content) = cycler.display(at: time(seconds)) else { return nil }
            return content
        }

        let a = task("a"), b = task("b"), c = task("c", started: 0.5)
        var stable = enabled([c, b, a])
        try expect(content(&stable, at: 0)?.taskID == a.id, "Task order must use startedAt then id")
        for second in 1...3 { stable.updateTasks([b, c, a], at: time(Double(second))) }
        try expect(content(&stable, at: 3.99)?.taskID == a.id, "Periodic identical snapshots must not reset rotation")
        try expect(content(&stable, at: 4)?.taskID == b.id, "Rotation must advance at four seconds")
        try expect(content(&stable, at: 8)?.taskID == c.id, "Rotation must advance to the third task")
        try expect(content(&stable, at: 12)?.taskID == a.id, "Rotation must wrap around")

        var metadata = enabled([a, b])
        metadata.updateTasks([task("a", updated: 3, phase: .executing, completed: 1, total: 4), b], at: time(3))
        let changed = content(&metadata, at: 3)
        try expect(changed?.taskID == a.id && changed?.phaseLabel == AgentTaskPhase.executing.label, "Metadata updates must refresh the visible task")
        try expect(changed?.planLabel == "计划步骤 1/4" && changed?.planFraction == 0.25, "Only real plan step counts may fill a determinate bar")
        try expect(content(&metadata, at: 4)?.taskID == b.id, "Phase/plan updates must not reset the deadline")

        var removal = enabled([a, b, c])
        _ = removal.nextTask(at: time(1))
        removal.updateTasks([a, c], at: time(2))
        let successor = content(&removal, at: 2)
        try expect(successor?.taskID == c.id && successor?.indexLabel == "2/2", "A finishing visible task must immediately select the next survivor")
        removal.updateTasks([], at: time(3))
        try expect(removal.display(at: time(3)) == nil, "No active tasks must leave no working bubble")
        removal.updateTasks([b], at: time(4))
        try expect(content(&removal, at: 4)?.taskID == b.id, "New tasks after an empty list must appear immediately")

        var transient = enabled([a, b])
        transient.showMessage("本轮已完成", at: time(1))
        try expect(transient.display(at: time(7.99)) == .message("本轮已完成"), "Temporary speech must have seven-second priority")
        try expect(!transient.nextTask(at: time(2)), "A temporary message must not allow a hidden task click")
        try expect(content(&transient, at: 8)?.taskID == a.id, "The original task must resume after speech")
        try expect(content(&transient, at: 10.99)?.taskID == a.id, "Hidden time must not consume the rotation interval")
        try expect(content(&transient, at: 11)?.taskID == b.id, "Rotation must resume using its remaining visible duration")

        var extendedSpeech = enabled([a, b])
        extendedSpeech.showMessage("第一句", at: time(1))
        extendedSpeech.showMessage("第二句", at: time(4))
        try expect(extendedSpeech.display(at: time(10.9)) == .message("第二句"), "Replacing speech must extend message priority")
        try expect(content(&extendedSpeech, at: 11)?.taskID == a.id, "Extended speech must resume the previous task")
        try expect(content(&extendedSpeech, at: 14)?.taskID == b.id, "Extended speech must pause, not restart, rotation")

        var hidden = enabled([a, b])
        hidden.setProgressVisible(false, at: time(1))
        try expect(hidden.display(at: time(9)) == nil, "Do-not-disturb must hide the full working bubble")
        hidden.setProgressVisible(true, at: time(10))
        try expect(content(&hidden, at: 10)?.taskID == a.id, "Visibility restoration must preserve the selected task")
        try expect(content(&hidden, at: 13)?.taskID == b.id, "Hidden time must not advance the carousel")
        hidden.setProgressEnabled(false, at: time(14))
        try expect(hidden.tasks.isEmpty && hidden.display(at: time(14)) == nil, "Disconnect/switch-off must clear work state immediately")
        hidden.updateTasks([a, b], at: time(15))
        hidden.setProgressEnabled(true, at: time(16))
        try expect(hidden.display(at: time(16)) == nil, "Re-enable must not resurrect an old task snapshot")
        hidden.updateTasks([b], at: time(16))
        try expect(content(&hidden, at: 16)?.taskID == b.id, "Re-enable must accept a fresh task snapshot")

        var manual = enabled([a, b, c])
        try expect(manual.nextTask(at: time(1)), "Manual switching must accept a visible work bubble")
        try expect(content(&manual, at: 1)?.taskID == b.id, "Manual switching must select the next task")
        try expect(content(&manual, at: 4.99)?.taskID == b.id, "A clicked task must receive its own four-second interval")
        try expect(content(&manual, at: 5)?.taskID == c.id, "Automatic cycling must resume after a click")

        var insertion = enabled([a, b])
        _ = insertion.nextTask(at: time(1))
        insertion.updateTasks([task("earlier", started: -5), b, a], at: time(2))
        try expect(content(&insertion, at: 2)?.taskID == b.id, "An inserted task must not steal the visible task")
        try expect(content(&insertion, at: 2)?.indexLabel == "3/3", "The rotation index must match stable task order")
        var deduped = enabled([task("a", updated: 0, title: "旧标题"), task("a", updated: 2, title: "新标题")])
        try expect(deduped.tasks.count == 1 && content(&deduped, at: 2)?.title == "新标题", "Duplicate IDs must use their most recent metadata")

        var invalidPlan = enabled([task("a", completed: 5, total: 4)])
        try expect(content(&invalidPlan, at: 0)?.planFraction == nil, "Invalid plan counts must stay indeterminate")
        invalidPlan.updateTasks([task("a", completed: 0, total: 0)], at: time(1))
        try expect(content(&invalidPlan, at: 1)?.planLabel == nil, "An empty plan must not invent progress")
        invalidPlan.updateTasks([task("a", completed: nil, total: 3)], at: time(2))
        try expect(content(&invalidPlan, at: 2)?.planFraction == nil, "Partial plan metadata must not invent progress")

        var elapsed = enabled([task("future", started: 100, title: " \n ")])
        let future = content(&elapsed, at: 0)
        try expect(future?.elapsedSeconds == 0 && future?.title == "Agent 任务", "Future timestamps and blank titles must be safe")
        elapsed.updateTasks([task("a", phase: .editing, completed: 2, total: 5)], at: time(0))
        let hour = content(&elapsed, at: 3661)
        try expect(hour?.elapsedLabel == "1小时01分", "Elapsed labels must support long tasks")
        try expect(hour?.accessibilityValue.contains("计划步骤 2/5") == true && hour?.accessibilityValue.contains("任务 1/1") == true,
                   "Accessibility must expose actual plan steps and rotation index")
        try expect(hour?.accessibilityValue.contains("%") == false, "No overall completion percentage may be invented")

        var delayedTimer = enabled([a, b, c])
        try expect(content(&delayedTimer, at: 20)?.taskID == c.id, "A delayed tick must advance deterministically without timing drift")
        var ordinarySpeech = enabled([a])
        ordinarySpeech.showMessage("你好", at: time(1))
        ordinarySpeech.setProgressEnabled(false, at: time(2))
        try expect(ordinarySpeech.display(at: time(2)) == .message("你好"), "Turning off work progress must not erase manual companion speech")
        try expect(ordinarySpeech.display(at: time(8)) == nil, "Expired manual speech must clear with progress disabled")

        print("PASS: \(assertions) task-bubble assertions — stable rotation, metadata refresh, task removal, speech priority, DND, disconnect, manual switching, plan semantics, and accessibility")
    }
}
