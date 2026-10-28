import Foundation

private struct LifeFailure: Error, CustomStringConvertible { let description: String }

@main struct LifeCoreTests {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("xiaoke-life-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 14))!
        var assertions = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
            assertions += 1
            guard value() else { throw LifeFailure(description: message) }
        }
        func quiet(_ store: CompanionStore) {
            var settings = store.state.settings
            settings.interactionFrequency = 0
            settings.restReminderMinutes = 0
            settings.doNotDisturbEnabled = false
            store.updateSettings(settings)
            while store.toast != nil { store.dismissToast() }
        }
        func newStore(_ name: String, time: @escaping () -> Date) -> CompanionStore {
            let store = CompanionStore(directory: root.appendingPathComponent(name), now: time, calendar: calendar)
            quiet(store)
            return store
        }
        func write(_ state: CompanionState, to url: URL) throws {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
            try encoder.encode(state).write(to: url)
        }

        do {
            let store = newStore("decor", time: { base })
            try expect(store.state.life.homeItems == Set(PetHomeItem.allCases), "new home should contain all four comforts")
            store.setHomeItem(.lamp, enabled: false)
            store.setHomeItem(.blanket, enabled: false)
            for accessory in PetAccessory.allCases { store.setAccessory(accessory, enabled: true) }
            store.setSeason(.winter)
            let reloaded = CompanionStore(directory: store.directory, now: { base }, calendar: calendar)
            try expect(reloaded.state.life.homeItems == [.cushion, .desk], "home choices must survive reload")
            try expect(reloaded.state.life.accessories == Set(PetAccessory.allCases), "all accessories may coexist")
            try expect(reloaded.state.life.season == .winter, "season persists")
            reloaded.applySeasonalOutfit()
            try expect(reloaded.state.life.accessories == [.scarf, .sleepCap, .blanket], "winter preset")
            reloaded.setSeason(.summer); reloaded.applySeasonalOutfit()
            try expect(reloaded.state.life.accessories == [.bow], "summer preset")
            try expect(reloaded.state.stats.experience == 0, "decorating must not farm experience")
        }

        do {
            let store = newStore("migration", time: { base })
            let note = store.addNote(title: "保留的便签", text: "旧存档数据")
            var object = try JSONSerialization.jsonObject(with: Data(contentsOf: store.saveURL)) as! [String: Any]
            object.removeValue(forKey: "life")
            try JSONSerialization.data(withJSONObject: object).write(to: store.saveURL)
            let migrated = CompanionStore(directory: store.directory, now: { base }, calendar: calendar)
            try expect(migrated.persistenceError == nil, "legacy save should migrate without corruption warning")
            try expect(migrated.state.notes.first?.id == note && migrated.state.life == PetLife(), "migration preserves old data")
            object["life"] = ["homeItems": ["lamp"], "season": "spring"]
            let partial = root.appendingPathComponent("partial.json")
            try JSONSerialization.data(withJSONObject: object).write(to: partial)
            try migrated.importState(from: partial)
            try expect(migrated.state.life.homeItems == [.lamp] && migrated.state.life.season == .spring, "partial additions preserve supplied values")
            try expect(migrated.state.life.accessories == [.bow], "partial additions receive absent defaults")
            let before = migrated.state
            object["life"] = ["homeItems": ["unknown-furniture"]]
            try JSONSerialization.data(withJSONObject: object).write(to: partial)
            var rejected = false
            do { try migrated.importState(from: partial) } catch { rejected = true }
            try expect(rejected && migrated.state == before, "unknown home entries must reject atomically")
            object["life"] = ["contentment": 101]
            try JSONSerialization.data(withJSONObject: object).write(to: partial)
            rejected = false
            do { try migrated.importState(from: partial) } catch { rejected = true }
            try expect(rejected && migrated.state == before, "invalid mood value must reject atomically")
            object["life"] = ["gameBestScores": ["stars": 1001]]
            try JSONSerialization.data(withJSONObject: object).write(to: partial)
            rejected = false
            do { try migrated.importState(from: partial) } catch { rejected = true }
            try expect(rejected && migrated.state == before, "invalid imported score must reject")
        }

        do {
            var time = base
            let store = newStore("food", time: { time })
            try expect(store.favoriteFood == .cookie, "initial favorite should be cookie")
            try expect(store.feed(.cookie), "favorite feeding accepted")
            try expect(store.animationRequest?.state == "eat-cookie" && store.animationRequest?.duration == 6.5, "food requests real eating sequence")
            try expect(store.petMood == .cheerful && store.state.life.foodServings["cookie"] == 1, "favorite changes visible mood and memory")
            let life = store.state.life
            try expect(!store.feed(.cookie) && store.state.life == life, "blocked feeding cannot farm mood/preference")
            try expect(store.feed(.water) && store.animationRequest?.state == "drink-water", "water uses cup animation")
            time = time.addingTimeInterval(301)
            try expect(store.feed(.milk) && store.animationRequest?.state == "drink-milk", "milk uses drink animation although calorie cooldown is shared")
            try expect(store.foodPreference(.cookie).contains("最喜欢"), "preference explanation exposed")
            store.setCompanionWorking(true)
            try expect(store.contextualWish.contains("陪你"), "working wish stays quiet and contextual")
            let reloaded = CompanionStore(directory: store.directory, now: { time }, calendar: calendar)
            try expect(reloaded.state.life.foodServings == store.state.life.foodServings, "food memories persist")
        }

        do {
            var time = base
            let store = newStore("touch", time: { time })
            try expect(store.touchPet(zone: "head") && store.animationRequest?.state == "touch-head", "head zone responds and rewards")
            let xp = store.state.stats.experience
            time = time.addingTimeInterval(1)
            try expect(!store.touchPet(zone: "face") && store.animationRequest?.state == "touch-face", "face responds during reward cooldown")
            time = time.addingTimeInterval(1)
            try expect(!store.touchPet(zone: "book") && store.animationRequest?.state == "touch-book", "book has its own response")
            time = time.addingTimeInterval(1)
            try expect(!store.touchPet(zone: "head") && store.animationRequest?.state == "dodge", "four quick touches trigger gentle dodge")
            try expect(store.petMood == .shy && store.state.stats.experience == xp, "rapid touches cannot farm rewards")
            let before = store.state
            try expect(!store.touchPet(zone: "bubble") && store.state == before, "non-pet touch zone ignored")
            time = time.addingTimeInterval(10)
            try expect(store.touchPet(zone: "face") && store.petMood != .shy, "touch cooldown and shy mood recover")
            let knownAnimation = store.animationRequest
            store.performDailyAction("invalid-action")
            try expect(store.animationRequest == knownAnimation, "unrecognized daily action ignored")
            for action in ["rub-eyes", "stretch", "page-flip", "groom", "yawn"] {
                store.performDailyAction(action)
                try expect(store.animationRequest?.state == action, "daily action \(action) dispatch")
            }
        }

        do {
            var time = base
            let store = newStore("games", time: { time })
            let id = store.beginGame(.stars)
            try expect(store.resumeGame(sessionID: id), "already-running valid session is resumable")
            try expect(!store.recordGameResult(kind: .stars, score: 20, sessionID: id), "instant game result rejected")
            time = time.addingTimeInterval(60)
            try expect(!store.recordGameResult(kind: .hands, score: 20, sessionID: id), "wrong game rejected")
            try expect(!store.recordGameResult(kind: .stars, score: -1, sessionID: id), "negative score rejected")
            try expect(!store.recordGameResult(kind: .stars, score: 1001, sessionID: id), "out-of-range score rejected")
            try expect(!store.recordGameResult(kind: .stars, score: 20, sessionID: UUID()), "foreign session rejected")
            try expect(store.recordGameResult(kind: .stars, score: 20, sessionID: id), "complete session recorded")
            try expect(store.gameBestScore(.stars) == 20 && store.state.stats.experience == 2, "first daily result saves score and reward")
            try expect(!store.gameRewardAvailable(.stars), "first daily reward consumed")
            try expect(!store.recordGameResult(kind: .stars, score: 100, sessionID: id), "same session cannot reward twice")
            let repeatID = store.beginGame(.stars)
            time = time.addingTimeInterval(60)
            try expect(store.recordGameResult(kind: .stars, score: 10, sessionID: repeatID), "repeat game records normally")
            try expect(store.gameBestScore(.stars) == 20 && store.state.stats.experience == 2, "repeat retains best without farming XP")
            let paused = store.beginGame(.hands)
            time = time.addingTimeInterval(20); store.pauseGame(sessionID: paused)
            time = time.addingTimeInterval(120)
            try expect(!store.recordGameResult(kind: .hands, score: 10, sessionID: paused), "paused wall time must not count")
            store.resumeGame(sessionID: paused); time = time.addingTimeInterval(40)
            try expect(store.recordGameResult(kind: .hands, score: 10, sessionID: paused), "active intervals combine to one minute")
            let workPaused = store.beginGame(.cookie)
            time = time.addingTimeInterval(20); store.setCompanionWorking(true)
            time = time.addingTimeInterval(100); store.resumeGame(sessionID: workPaused)
            time = time.addingTimeInterval(100)
            try expect(!store.recordGameResult(kind: .cookie, score: 10, sessionID: workPaused), "work pauses game and blocks resume")
            store.setCompanionWorking(false); store.resumeGame(sessionID: workPaused)
            time = time.addingTimeInterval(40)
            try expect(store.recordGameResult(kind: .cookie, score: 10, sessionID: workPaused), "manual resume after work can finish")
            try expect(store.state.stats.experience == 6, "three daily games total six XP")
            let cancelled = store.beginGame(.stars); store.cancelGame(sessionID: cancelled)
            try expect(!store.resumeGame(sessionID: cancelled), "cancelled session reports resume failure")
            time = time.addingTimeInterval(60)
            try expect(!store.recordGameResult(kind: .stars, score: 10, sessionID: cancelled), "cancelled game cannot submit")
            time = time.addingTimeInterval(86400)
            try expect(store.gameRewardAvailable(.stars), "next calendar day restores reward")
            let zero = store.beginGame(.stars); time = time.addingTimeInterval(60)
            try expect(store.recordGameResult(kind: .stars, score: 0, sessionID: zero) && store.gameRewardAvailable(.stars), "zero-score game records without consuming reward")
            let nextDay = store.beginGame(.stars); time = time.addingTimeInterval(60)
            try expect(store.recordGameResult(kind: .stars, score: 30, sessionID: nextDay), "next day's completed game accepted")
            try expect(store.state.stats.experience == 8 && store.gameBestScore(.stars) == 30, "next day can reward and update best")
            let reloaded = CompanionStore(directory: store.directory, now: { time }, calendar: calendar)
            try expect(reloaded.gameBestScore(.stars) == 30 && !reloaded.gameRewardAvailable(.stars), "game progress survives restart")
            let stale = store.beginGame(.cookie)
            store.pauseGame(sessionID: stale)
            let exported = root.appendingPathComponent("game-import.json")
            try store.exportState(to: exported)
            try store.importState(from: exported)
            try expect(!store.resumeGame(sessionID: stale), "import invalidates an earlier in-memory session")
        }

        do {
            let store = newStore("mood", time: { base })
            let fixture = root.appendingPathComponent("mood.json")
            var state = store.state
            state.stats.energy = 10
            try write(state, to: fixture); try store.importState(from: fixture)
            try expect(store.petMood == .sleepy && store.contextualWish.contains("睡帽"), "low energy mood and wish")
            state.stats.energy = 80; state.stats.hunger = 90
            try write(state, to: fixture); try store.importState(from: fixture)
            try expect(store.petMood == .hungry && store.contextualWish.contains("饭团"), "hunger mood and wish")
        }
        print("PASS life core: \(assertions) assertions (migration, decor, mood, feeding, touch, timed games)")
    }
}
