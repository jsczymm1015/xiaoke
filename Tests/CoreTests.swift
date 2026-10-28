import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

@main struct CoreTests {
    @MainActor static func main() throws {
        var passed = 0
        var failures: [String] = []
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("xiaoke-core-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 9))!

        func expect(_ condition: @autoclosure () -> Bool, _ reason: String) throws {
            if !condition() { throw TestFailure(description: reason) }
        }
        func test(_ name: String, _ body: (URL) throws -> Void) {
            let directory = parent.appendingPathComponent(UUID().uuidString)
            do {
                try body(directory)
                passed += 1
                print("PASS \(name)")
            } catch {
                failures.append("\(name): \(error)")
                print("FAIL \(name): \(error)")
            }
        }
        func silence(_ store: CompanionStore) {
            var settings = store.state.settings
            settings.interactionFrequency = 0
            settings.restReminderMinutes = 0
            settings.doNotDisturbEnabled = false
            store.updateSettings(settings)
            while store.toast != nil { store.dismissToast() }
        }

        test("CRUD + settings reload") { directory in
            var time = base
            let store = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            silence(store)
            let todo = store.addTodo(title: "草稿", details: "段落", dueAt: base.addingTimeInterval(100))
            store.updateTodo(id: todo, title: "终稿", details: "检查", dueAt: base.addingTimeInterval(300))
            let note = store.addNote(title: "提示", text: "不要忘记喝水")
            store.updateNote(id: note, title: "喝水", text: "每天")
            store.toggleNotePinned(id: note)
            let habit = store.addHabit(title: "读书")
            store.updateHabit(id: habit, title: "读一页")
            let shortcut = store.addShortcut(label: "文档", path: "/tmp/example")
            store.updateShortcut(id: shortcut, label: "常用文档", path: "/tmp/updated")
            var settings = store.state.settings
            settings.nickname = "小云"
            settings.scale = 1.2
            settings.petX = 150
            settings.petY = 250
            settings.mouseFollow = false
            settings.clickThrough = true
            store.updateSettings(settings)
            time = time.addingTimeInterval(10)
            let loaded = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            try expect(loaded.state.todos.first?.title == "终稿", "todo reload")
            try expect(loaded.state.todos.first?.details == "检查", "todo edit")
            try expect(loaded.state.notes.first?.isPinned == true, "note pin reload")
            try expect(loaded.state.habits.first?.title == "读一页", "habit edit")
            try expect(loaded.state.shortcuts.first?.path == "/tmp/updated", "shortcut edit")
            try expect(loaded.state.settings.nickname == "小云" && loaded.state.settings.petX == 150, "settings reload")
            loaded.deleteTodo(id: todo); loaded.deleteNote(id: note); loaded.deleteHabit(id: habit); loaded.deleteShortcut(id: shortcut)
            let empty = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            try expect(empty.state.todos.isEmpty && empty.state.notes.isEmpty && empty.state.habits.isEmpty && empty.state.shortcuts.isEmpty, "delete persisted")
        }

        test("appearance selection reloads without resetting shared companion data") { directory in
            let store = CompanionStore(directory: directory, now: { base }, calendar: calendar)
            silence(store)
            let todo = store.addTodo(title: "共享待办", details: "两种外观使用同一份记录")
            store.setTodoCompleted(id: todo, completed: true)
            _ = store.addNote(title: "共享便签", text: "不会重置")
            let habit = store.addHabit(title: "共享习惯")
            _ = store.checkInHabit(id: habit)
            _ = store.addShortcut(label: "共享入口", path: "/tmp/shared")
            _ = store.interact(.feed)
            store.startPomodoro(minutes: 25)
            let before = store.state
            var settings = store.state.settings
            settings.appearance = .l3d
            store.updateSettings(settings)
            let loaded = CompanionStore(directory: directory, now: { base }, calendar: calendar)
            var expected = before
            expected.settings.appearance = .l3d
            try expect(loaded.state == expected, "appearance reload reset progress or records")
            try expect(loaded.companionName == "小可 · 小馆员" && loaded.companionShortName == "小可", "appearance name did not update")
            settings = loaded.state.settings
            settings.appearance = .whiteDragon
            loaded.updateSettings(settings)
            try expect(loaded.companionName == "小可 · 白龙" && loaded.state.stats == before.stats, "switching back changed progress")
        }

        test("legacy save and import fill new setting defaults without corruption") { directory in
            let store = CompanionStore(directory: directory, now: { base }, calendar: calendar)
            silence(store)
            _ = store.addTodo(title: "旧存档待办")
            var original = store.state
            original.settings.appearance = .whiteDragon // Saves predating appearance selection used white dragon.
            var object = try JSONSerialization.jsonObject(with: Data(contentsOf: store.saveURL)) as! [String: Any]
            var settings = object["settings"] as! [String: Any]
            settings.removeValue(forKey: "appearance")
            settings.removeValue(forKey: "hardwareHover")
            settings.removeValue(forKey: "codexTaskReminders")
            settings.removeValue(forKey: "codexProgressBubble")
            object["settings"] = settings
            let legacyData = try JSONSerialization.data(withJSONObject: object)
            try legacyData.write(to: store.saveURL)
            let loaded = CompanionStore(directory: directory, now: { base }, calendar: calendar)
            try expect(loaded.persistenceError == nil && loaded.state == original, "legacy save treated as corrupt")
            try expect(loaded.state.settings.appearance == .whiteDragon && loaded.state.settings.hardwareHover && loaded.state.settings.codexTaskReminders && loaded.state.settings.codexProgressBubble, "migration defaults wrong")
            let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains("corrupt-") }
            try expect(backups.isEmpty, "legacy save generated a corrupt backup")
            let legacyImport = directory.appendingPathComponent("legacy-import.json")
            try legacyData.write(to: legacyImport)
            var current = loaded.state.settings
            current.appearance = .l3d
            loaded.updateSettings(current)
            try loaded.importState(from: legacyImport)
            try expect(loaded.state == original && loaded.persistenceError == nil, "legacy import not migrated")
        }

        test("Codex completion reminds without awarding progress and respects switches") { directory in
            let store = CompanionStore(directory: directory, now: { base }, calendar: calendar)
            silence(store)
            let stats = store.state.stats
            store.notifyCodexTurnEnded(.completed)
            try expect(store.toast?.text.contains("这一轮已结束") == true, "completion bubble missing")
            try expect(store.toast?.notifySystem == true && store.toast?.codexTaskEvent == true, "notification routing missing")
            try expect(store.state.stats == stats && store.state.dailyProgress.isEmpty, "external turn awarded progress")
            store.dismissToast()
            var settings = store.state.settings
            settings.codexTaskReminders = false
            store.updateSettings(settings)
            store.notifyCodexTurnEnded(.failed)
            try expect(store.toast == nil, "disabled Codex switch still reminded")
            settings.codexTaskReminders = true
            settings.remindersEnabled = false
            store.updateSettings(settings)
            store.notifyCodexTurnEnded(.completed)
            try expect(store.toast == nil, "disabled master switch still reminded")
            settings.remindersEnabled = true
            settings.doNotDisturbEnabled = true
            settings.quietStartHour = 0; settings.quietEndHour = 0
            store.updateSettings(settings)
            store.notifyCodexTurnEnded(.completed)
            try expect(store.toast == nil, "quiet time still reminded")
            settings.doNotDisturbEnabled = false
            store.updateSettings(settings)
            store.notifyCodexTurnEnded(.failed)
            try expect(store.toast?.text.contains("错误") == true && store.animationRequest?.state == "failed", "failed turn was announced as success")
            let loaded = CompanionStore(directory: directory, now: { base }, calendar: calendar)
            try expect(loaded.state.settings.codexTaskReminders, "Codex toggle failed to reload")
        }

        test("working bubble can be disabled while completion reminders stay enabled") { directory in
            let store = CompanionStore(directory: directory, now: { base }, calendar: calendar)
            silence(store)
            var settings = store.state.settings
            settings.codexProgressBubble = false
            store.updateSettings(settings)
            let loaded = CompanionStore(directory: directory, now: { base }, calendar: calendar)
            try expect(!loaded.state.settings.codexProgressBubble && loaded.state.settings.codexTaskReminders, "working-bubble preference changed completion monitoring")
            loaded.notifyCodexTurnEnded(.completed)
            try expect(loaded.toast?.text.contains("这一轮已结束") == true, "disabling the working bubble suppressed completion reminders")
        }

        test("queued Codex notification is dropped when its switch turns off") { directory in
            let store = CompanionStore(directory: directory, now: { base }, calendar: calendar)
            silence(store)
            _ = store.interact(.pet)
            store.notifyCodexTurnEnded(.completed)
            var settings = store.state.settings
            settings.codexTaskReminders = false
            store.updateSettings(settings)
            store.dismissToast()
            try expect(store.toast == nil, "queued Codex reminder survived disabled toggle")
        }

        test("unknown explicit appearance remains an invalid import") { directory in
            let store = CompanionStore(directory: directory, now: { base }, calendar: calendar)
            silence(store)
            let before = store.state
            var object = try JSONSerialization.jsonObject(with: Data(contentsOf: store.saveURL)) as! [String: Any]
            var settings = object["settings"] as! [String: Any]
            settings["appearance"] = "unknown-avatar"
            object["settings"] = settings
            let invalid = directory.appendingPathComponent("invalid-appearance.json")
            try JSONSerialization.data(withJSONObject: object).write(to: invalid)
            var rejected = false
            do { try store.importState(from: invalid) } catch { rejected = true }
            try expect(rejected && store.state == before, "unknown explicit value was silently migrated")
        }

        test("completion reward cannot be farmed") { directory in
            let store = CompanionStore(directory: directory, now: { base }, calendar: calendar)
            silence(store)
            let id = store.addTodo(title: "写报告")
            store.setTodoCompleted(id: id, completed: true)
            let earned = store.state.stats.experience
            store.setTodoCompleted(id: id, completed: true)
            store.setTodoCompleted(id: id, completed: false)
            store.setTodoCompleted(id: id, completed: true)
            try expect(earned == 15 && store.state.stats.experience == earned, "repeated complete granted XP")
            let loaded = CompanionStore(directory: directory, now: { base }, calendar: calendar)
            loaded.setTodoCompleted(id: id, completed: false)
            loaded.setTodoCompleted(id: id, completed: true)
            try expect(loaded.state.stats.experience == 15 && loaded.todayProgress.todosCompleted == 1, "reward flag lost on reload")
        }

        test("deadline suppressed in quiet hours then delivered once") { directory in
            var time = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 23))!
            let store = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            var settings = store.state.settings
            settings.interactionFrequency = 0; settings.restReminderMinutes = 0
            store.updateSettings(settings)
            let id = store.addTodo(title: "约定", dueAt: time.addingTimeInterval(-1))
            store.tick()
            try expect(store.toast == nil, "quiet hours showed deadline toast")
            try expect(store.state.todos[0].dueReminderSent == false, "suppression consumed reminder")
            time = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 8))!
            store.tick()
            try expect(store.toast?.text.contains("约定") == true, "deferred reminder missing")
            try expect(store.state.todos[0].dueReminderSent, "reminder flag missing")
            store.dismissToast(); store.tick()
            try expect(store.toast == nil, "reminder repeated")
            let loaded = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            try expect(loaded.toast == nil, "reminder repeated after restart")
            loaded.updateTodo(id: id, title: "约定", dueAt: time.addingTimeInterval(10))
            time = time.addingTimeInterval(11); loaded.tick()
            try expect(loaded.toast?.text.contains("约定") == true, "edited deadline not reminded")
        }

        test("queued automatic reminder is skipped across 22:00 quiet boundary") { directory in
            var time = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 21, minute: 59, second: 59))!
            let store = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            silence(store)
            var settings = store.state.settings
            settings.doNotDisturbEnabled = true
            settings.quietStartHour = 22; settings.quietEndHour = 8
            store.updateSettings(settings)
            _ = store.interact(.pet)
            _ = store.addTodo(title: "已排队的截止提醒", dueAt: time)
            store.tick()
            try expect(store.state.events.contains(where: { $0.text.contains("已排队的截止提醒") && $0.text.contains("截止提醒") }), "reminder did not enter queue before quiet time")
            time = time.addingTimeInterval(2)
            store.dismissToast()
            try expect(store.toast == nil, "queued automatic reminder displayed after 22:00")
            store.tick()
            try expect(store.toast == nil, "skipped reminder unexpectedly repeated")
        }

        test("queued explicit interaction still displays during quiet hours") { directory in
            var time = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 21, minute: 59, second: 59))!
            let store = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            silence(store)
            var settings = store.state.settings
            settings.doNotDisturbEnabled = true
            settings.quietStartHour = 22; settings.quietEndHour = 8
            store.updateSettings(settings)
            _ = store.interact(.pet)
            _ = store.addTodo(title: "应跳过的提醒", dueAt: time)
            store.tick()
            _ = store.interact(.feed)
            time = time.addingTimeInterval(2)
            store.dismissToast()
            try expect(store.toast?.text.contains("谢谢投喂") == true && store.toast?.notifySystem == false, "explicit interaction was suppressed along with automatic reminder")
        }

        test("queued automatic reminder is skipped when reminders become disabled") { directory in
            let store = CompanionStore(directory: directory, now: { base }, calendar: calendar)
            silence(store)
            _ = store.interact(.pet)
            _ = store.addTodo(title: "关闭提醒后应跳过", dueAt: base)
            store.tick()
            var settings = store.state.settings
            settings.remindersEnabled = false
            store.updateSettings(settings)
            store.dismissToast()
            try expect(store.toast == nil, "queued automatic reminder displayed despite disabled reminders")
        }

        test("paused focus survives restart") { directory in
            var time = base
            let store = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            silence(store)
            store.startPomodoro(minutes: 1, breakMinutes: 1)
            time = time.addingTimeInterval(20); store.pausePomodoro()
            try expect(abs(store.pomodoroRemainingSeconds - 40) < 0.001, "pause remaining wrong")
            time = time.addingTimeInterval(3600)
            let loaded = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            try expect(loaded.state.pomodoro?.isPaused == true && loaded.pomodoroRemainingSeconds == 40, "restart advanced paused timer")
            loaded.resumePomodoro()
            time = time.addingTimeInterval(39); loaded.tick()
            try expect(loaded.state.pomodoro?.phase == .work && loaded.state.stats.experience == 0, "settled before deadline")
            time = time.addingTimeInterval(1); loaded.tick()
            try expect(loaded.state.pomodoro?.phase == .rest && loaded.state.stats.experience == 10, "focus did not settle")
            try expect(loaded.todayProgress.focusMinutes == 1, "focus statistics missing")
        }

        test("pause on an already expired session saves settlement") { directory in
            var time = base
            let store = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            silence(store); store.startPomodoro(minutes: 1, breakMinutes: 1)
            time = time.addingTimeInterval(121)
            store.pausePomodoro()
            let loaded = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            try expect(loaded.state.stats.experience == 10, "pause lost or duplicated settlement")
            try expect(loaded.state.events.filter { $0.text.contains("完成 1 分钟专注") }.count == 1, "pause did not persist settlement")
        }

        test("expired focus recovers and settles exactly once") { directory in
            var time = base
            let store = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            silence(store); store.startPomodoro(minutes: 1, breakMinutes: 1)
            time = time.addingTimeInterval(121)
            let first = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            try expect(first.state.pomodoro == nil && first.state.stats.experience == 10, "expired timer not settled")
            first.tick(); first.tick()
            let second = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            try expect(second.state.stats.experience == 10 && second.todayProgress.focusMinutes == 1, "duplicate focus reward")
            try expect(second.state.events.filter { $0.text.contains("完成 1 分钟专注") }.count == 1, "duplicate settlement record")
            second.startPomodoro(minutes: 1)
            second.cancelPomodoro()
            time = time.addingTimeInterval(1000); second.tick()
            try expect(second.state.stats.experience == 10, "cancelled focus granted reward")
        }

        test("daily habit rejects same day and survives restart") { directory in
            var time = base
            let store = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            silence(store)
            let id = store.addHabit(title: "阅读")
            try expect(store.checkInHabit(id: id), "first checkin rejected")
            try expect(!store.checkInHabit(id: id), "same day checkin accepted")
            let loaded = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            try expect(!loaded.checkInHabit(id: id) && loaded.state.stats.experience == 5, "reload repeated checkin")
            time = time.addingTimeInterval(86400)
            try expect(loaded.checkInHabit(id: id), "new day rejected")
            try expect(loaded.state.stats.experience == 10 && loaded.todayProgress.habitCheckIns == 1, "new day statistics wrong")
            time = base
            try expect(!loaded.checkInHabit(id: id), "clock rollback rewarded old day")
        }

        test("interaction cooldown and bounded stats") { directory in
            var time = base
            let store = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            silence(store)
            try expect(store.interact(.pet), "first pet rejected")
            try expect(!store.interact(.pet), "cooldown bypassed")
            let loaded = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            try expect(!loaded.interact(.pet), "reload reset cooldown")
            time = time.addingTimeInterval(8)
            try expect(loaded.interact(.pet), "cooldown did not expire")
            time = time.addingTimeInterval(86400 * 365); loaded.tick()
            try expect(loaded.state.stats.hunger == 100 && loaded.state.stats.energy == 0, "stats unbounded")
            try expect(loaded.interact(.feed) && loaded.state.stats.hunger == 70, "feed effect wrong")
            try expect(loaded.interact(.rest) && loaded.state.stats.energy == 25, "rest effect wrong")
            let stats = loaded.state.stats
            time = base; loaded.tick()
            try expect(loaded.state.stats.hunger == stats.hunger && loaded.state.stats.energy == stats.energy, "clock rollback changed stats")
        }

        func seedFeedingState(_ directory: URL, hunger: Double = 80, energy: Double = 40,
                              affection: Int = 10, interactionDates: [String: Date] = [:]) throws {
            var fixture = CompanionState(now: base)
            fixture.stats.hunger = hunger
            fixture.stats.energy = energy
            fixture.stats.affection = affection
            fixture.stats.interactionDates = interactionDates
            fixture.notes = [NoteItem(title: "原有便签", text: "必须保留", updatedAt: base)]
            fixture.settings.interactionFrequency = 0
            fixture.settings.restReminderMinutes = 0
            fixture.settings.doNotDisturbEnabled = false
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(fixture).write(to: directory.appendingPathComponent("companion-state.json"))
        }

        test("food choices apply distinct effects and name their feedback") { directory in
            let cases: [(PetFood, Double, Double, Int, Int)] = [
                (.riceBall, 50, 45, 12, 1), (.sandwich, 40, 48, 12, 1),
                (.apple, 62, 46, 12, 1), (.cookie, 68, 43, 13, 1),
                (.cake, 60, 44, 14, 1), (.milk, 70, 52, 12, 1),
                (.water, 80, 43, 11, 0), (.herbalTea, 80, 48, 12, 0)
            ]
            for (food, hunger, energy, affection, experience) in cases {
                let folder = directory.appendingPathComponent(food.rawValue)
                try seedFeedingState(folder)
                let store = CompanionStore(directory: folder, now: { base }, calendar: calendar)
                silence(store)
                try expect(store.feed(food), "\(food) was rejected")
                try expect(store.state.stats.hunger == hunger && store.state.stats.energy == energy,
                           "\(food) applied wrong hunger/energy effects")
                try expect(store.state.stats.affection == affection && store.state.stats.experience == experience,
                           "\(food) applied wrong affection/experience effects")
                try expect(store.feedingHistory.first?.text.contains(food.title) == true, "food name missing from history")
                try expect(store.toast != nil && store.toast?.notifySystem == false, "feeding should show local explicit feedback")
                try expect(store.state.notes.first?.text == "必须保留", "feeding altered an existing note")
            }
        }

        test("food cooldown is shared, drinks independent and both survive reload") { directory in
            var time = base
            try seedFeedingState(directory)
            let store = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            silence(store)
            try expect(store.feed(.riceBall), "first food rejected")
            let foodStats = store.state.stats
            let foodHistory = store.feedingHistory
            try expect(!store.feed(.cake) && !store.feed(.milk), "changing food bypassed shared digestion cooldown")
            try expect(store.state.stats == foodStats && store.feedingHistory == foodHistory, "rejected food granted rewards or history")
            try expect(store.feedingCooldownRemaining(.apple) == 300, "food cooldown differs by food")
            try expect(store.feed(.water), "food incorrectly blocked a light drink")
            let drinkStats = store.state.stats
            try expect(!store.feed(.herbalTea) && store.state.stats == drinkStats, "switching light drink bypassed cooldown")
            let loaded = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            try expect(loaded.feedingCooldownRemaining(.sandwich) == 300 && loaded.feedingCooldownRemaining(.herbalTea) == 120,
                       "restart reset food or drink cooldown")
            time += 120
            try expect(loaded.feed(.herbalTea), "drink cooldown did not expire independently")
            try expect(!loaded.feed(.sandwich) && loaded.feedingCooldownRemaining(.sandwich) == 180,
                       "drink changed food cooldown")
            time += 180
            try expect(loaded.feed(.sandwich), "food cooldown failed to expire")
        }

        test("full pet refuses caloric foods without spending cooldown or rewards") { directory in
            try seedFeedingState(directory, hunger: 4, energy: 85)
            let store = CompanionStore(directory: directory, now: { base }, calendar: calendar)
            silence(store)
            let before = store.state.stats
            try expect(store.satiety == 96 && store.appetiteDescription.contains("还饱"), "fullness display inconsistent")
            try expect(store.feedingBlockReason(.cookie)?.contains("还饱") == true, "fullness reason missing")
            try expect(!store.feed(.cookie) && !store.feed(.milk), "full pet accepted food")
            try expect(store.state.stats == before && store.feedingHistory.isEmpty, "refusal altered rewards, dates, or history")
            try expect(store.feedingCooldownRemaining(.riceBall) == 0, "refusal consumed food cooldown")
            try expect(store.feed(.water), "fullness incorrectly blocked water")
            try expect(store.state.stats.hunger == 4 && store.state.stats.experience == 0, "water changed hunger or farmed experience")
        }

        test("feeding clamps state and reports only actual changes") { directory in
            try seedFeedingState(directory, hunger: 12, energy: 98, affection: 99)
            let store = CompanionStore(directory: directory, now: { base }, calendar: calendar)
            silence(store)
            try expect(store.feed(.sandwich), "small appetite rejected above threshold")
            try expect(store.state.stats.hunger == 0 && store.state.stats.energy == 100 && store.state.stats.affection == 100,
                       "feeding stats exceeded boundaries")
            let feedback = store.toast?.text ?? ""
            try expect(feedback.contains("饥饿 −12") && feedback.contains("精力 +2") && feedback.contains("好感 +1"),
                       "feedback overstated a clamped effect")
            try expect(!feedback.contains("饥饿 −40") && !feedback.contains("精力 +8"), "nominal effects leaked into actual result")
            try expect(store.satiety == 100, "maximum satiety wrong")
        }

        test("legacy feed cooldown and entry point retain compatibility") { directory in
            var time = base
            try seedFeedingState(directory, interactionDates: ["feed": base.addingTimeInterval(-60)])
            let store = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            silence(store)
            try expect(store.persistenceError == nil && store.state.notes.count == 1, "existing save was not preserved")
            try expect(store.feedingCooldownRemaining(.riceBall) == 240 && !store.interact(.feed), "legacy feed date was ignored")
            time += 240
            try expect(store.interact(.feed), "legacy feed entry no longer works")
            try expect(store.feedingHistory.first?.text.contains("饭团") == true, "legacy entry did not use new default food")
            let loaded = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            try expect(loaded.feedingHistory == store.feedingHistory && loaded.state.notes.first?.text == "必须保留",
                       "new feeding history failed to reload alongside old data")
        }

        test("feeding history shows newest six successful operations only") { directory in
            var time = base
            let store = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            silence(store)
            for index in 0..<8 {
                time = base.addingTimeInterval(Double(index * 121))
                try expect(store.feed(index.isMultiple(of: 2) ? .water : .herbalTea), "valid drink rejected")
                _ = store.addNote(title: "普通事件 \(index)")
                try expect(!store.feed(.water), "repeated drink accepted")
            }
            let history = store.feedingHistory
            try expect(history.count == 6, "history exceeded visible limit")
            try expect(history.first?.createdAt == base.addingTimeInterval(7 * 121) && history.last?.createdAt == base.addingTimeInterval(2 * 121),
                       "history not newest-first or included rejected actions")
            try expect(history.allSatisfy { $0.text.hasPrefix("喂养：") } && store.state.stats.experience == 0,
                       "ordinary events leaked into feeding history or drinks granted XP")
        }

        test("file success reward keyed by job") { directory in
            let store = CompanionStore(directory: directory, now: { base }, calendar: calendar)
            silence(store)
            let id = UUID()
            try expect(store.registerFileSuccess(jobID: id), "first job rejected")
            try expect(!store.registerFileSuccess(jobID: id), "duplicate job rewarded")
            let loaded = CompanionStore(directory: directory, now: { base }, calendar: calendar)
            try expect(!loaded.registerFileSuccess(jobID: id) && loaded.state.stats.experience == 3, "job reward lost after reload")
        }

        test("corrupt save is preserved before recovery") { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let corrupted = Data("{invalid json but preserve this}".utf8)
            try corrupted.write(to: directory.appendingPathComponent("companion-state.json"))
            let store = CompanionStore(directory: directory, now: { base }, calendar: calendar)
            let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains("corrupt-") }
            try expect(backups.count == 1, "backup missing")
            let preserved = try Data(contentsOf: backups[0])
            try expect(preserved == corrupted, "backup altered original")
            try expect(store.persistenceError?.contains("原文件已保留") == true, "no recovery message")
            let loaded = CompanionStore(directory: directory, now: { base }, calendar: calendar)
            try expect(loaded.persistenceError == nil, "recovered JSON unreadable")
        }

        test("rest reminders, quiet boundaries and settings validation") { directory in
            var time = base
            let store = CompanionStore(directory: directory, now: { time }, calendar: calendar)
            silence(store)
            var settings = store.state.settings
            settings.restReminderMinutes = 1
            settings.scale = 100; settings.quietStartHour = -3; settings.quietEndHour = 25
            settings.nickname = " "
            store.updateSettings(settings)
            try expect(store.state.settings.scale == 1.8 && store.state.settings.nickname == "你", "settings not bounded")
            time = time.addingTimeInterval(60); store.tick()
            try expect(store.toast?.text.contains("喝口水") == true, "rest reminder missing")
            store.dismissToast(); store.tick()
            try expect(store.toast == nil, "rest reminder repeated")
            settings = store.state.settings
            settings.doNotDisturbEnabled = true; settings.quietStartHour = 12; settings.quietEndHour = 14
            store.updateSettings(settings)
            let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))!
            let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 14))!
            try expect(store.isQuietTime(at: noon) && !store.isQuietTime(at: end), "nonwrapping quiet boundary wrong")
            settings.doNotDisturbEnabled = false
            try expect(!store.isQuietTime(at: noon, settings: settings) && store.isQuietTime(at: noon), "pending settings did not control quiet-time visibility independently")
        }

        test("event log stays bounded") { directory in
            let store = CompanionStore(directory: directory, now: { base }, calendar: calendar)
            silence(store)
            for i in 0..<215 { _ = store.addTodo(title: "任务 \(i)") }
            try expect(store.state.events.count == 200 && store.state.events.first?.text == "添加待办：任务 15", "event log cap wrong")
            let data = try Data(contentsOf: store.saveURL)
            let json = try JSONSerialization.jsonObject(with: data)
            try expect(json is [String: Any], "save not valid JSON")
        }

        test("backup failure never overwrites corrupt original") { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let original = Data("never overwrite this broken save".utf8)
            let save = directory.appendingPathComponent("companion-state.json")
            try original.write(to: save)
            let store = CompanionStore(directory: directory, now: { base }, calendar: calendar, backupFile: { _, _ in
                throw TestFailure(description: "injected backup failure")
            })
            _ = store.addTodo(title: "内存中的待办")
            store.tick(); store.save()
            let after = try Data(contentsOf: save)
            try expect(original == after, "failed backup allowed overwrite")
            try expect(store.persistenceError?.contains("备份失败") == true, "backup failure not visible")
            let export = directory.appendingPathComponent("safe-export.json")
            try store.exportState(to: export)
            try expect(FileManager.default.fileExists(atPath: export.path), "safe export unavailable")
        }

        test("import validates and backs up original before replacement") { directory in
            let store = CompanionStore(directory: directory, now: { base }, calendar: calendar)
            silence(store)
            _ = store.addTodo(title: "原待办")
            let originalBytes = try Data(contentsOf: store.saveURL)
            let other = CompanionStore(directory: directory.appendingPathComponent("other"), now: { base }, calendar: calendar)
            silence(other); _ = other.addNote(title: "导入便签", text: "新内容")
            let export = directory.appendingPathComponent("export.json")
            try other.exportState(to: export)
            try store.importState(from: export)
            try expect(store.state.todos.isEmpty && store.state.notes.first?.title == "导入便签", "import not applied")
            let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains("before-import-") }
            try expect(backups.count == 1, "import backup absent")
            let preserved = try Data(contentsOf: backups[0])
            try expect(preserved == originalBytes, "import original not preserved")
            let current = store.state
            var invalid = current
            invalid.stats.experience = -1
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
            let malformed = directory.appendingPathComponent("invalid.json")
            try encoder.encode(invalid).write(to: malformed)
            var rejected = false
            do { try store.importState(from: malformed) } catch { rejected = true }
            try expect(rejected && store.state == current, "invalid import changed state")
        }

        test("failed import backup preserves memory and existing disk") { directory in
            let store = CompanionStore(directory: directory, now: { base }, calendar: calendar, backupFile: { _, _ in
                throw TestFailure(description: "injected backup failure")
            })
            silence(store); _ = store.addTodo(title: "现存待办")
            let bytes = try Data(contentsOf: store.saveURL)
            let original = store.state
            let other = CompanionStore(directory: directory.appendingPathComponent("other"), now: { base }, calendar: calendar)
            silence(other); _ = other.addNote(title: "不应导入")
            let importURL = directory.appendingPathComponent("import.json")
            try other.exportState(to: importURL)
            var failed = false
            do { try store.importState(from: importURL) } catch { failed = true }
            let after = try Data(contentsOf: store.saveURL)
            try expect(failed && original == store.state && bytes == after, "failed import changed original")
        }

        test("locked actions enforce level without giving reward") { directory in
            let store = CompanionStore(directory: directory, now: { base }, calendar: calendar)
            silence(store)
            try expect(!store.performUnlockedAction(.secretLine), "locked action executed")
            try expect(store.performUnlockedAction(.greeting), "level 1 greeting unavailable")
            try expect(store.state.stats.experience == 0, "interaction action gives free XP")
            for i in 0..<10 {
                let id = store.addTodo(title: "真实任务 \(i)")
                store.setTodoCompleted(id: id, completed: true)
            }
            try expect(store.state.stats.level == 4 && store.performUnlockedAction(.secretLine), "earned action failed to unlock")
            try expect(store.state.stats.experience == 150, "unlocked action changed experience")
        }

        print("Core tests: \(passed) passed, \(failures.count) failed")
        if !failures.isEmpty { throw TestFailure(description: failures.joined(separator: "\n")) }
    }
}
