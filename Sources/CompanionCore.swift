import Foundation
import Combine

struct TodoItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var details = ""
    var dueAt: Date?
    var isCompleted = false
    var rewardGranted = false
    var createdAt: Date
    var dueReminderSent = false
}

struct NoteItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var text: String
    var isPinned = false
    var updatedAt: Date
}

struct HabitItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var checkIns: [String] = []
}

struct ShortcutItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var label: String
    var path: String
}

struct PetStats: Codable, Equatable {
    var experience = 0
    var affection = 10
    var hunger: Double = 25
    var energy: Double = 85
    var lastUpdatedAt: Date
    var interactionDates: [String: Date] = [:]
    var level: Int { 1 + experience / 50 }
}

enum PetAppearance: String, Codable, CaseIterable, Identifiable {
    case whiteDragon, l3d
    var id: String { rawValue }
    var title: String {
        switch self {
        case .whiteDragon: return "小可 · 白龙"
        case .l3d: return "小可 · 小馆员"
        }
    }
    var shortName: String {
        switch self {
        case .whiteDragon: return "小可"
        case .l3d: return "小可"
        }
    }
}

struct CompanionSettings: Codable, Equatable {
    var nickname = "你"
    var scale = 1.0
    var interactionFrequency = 0.35
    var doNotDisturbEnabled = true
    var quietStartHour = 22
    var quietEndHour = 8
    var clickThrough = false
    var remindersEnabled = true
    var codexTaskReminders = true
    var codexProgressBubble = true
    var mouseFollow = true
    var hardwareHover = true // Legacy save compatibility only; hardware is opened from the menu.
    var restReminderMinutes = 60
    var petVisible = true
    var petX: Double?
    var petY: Double?
    var nativeNotifications = false
    var appearance: PetAppearance = .l3d
}

enum PomodoroPhase: String, Codable { case work, rest }

struct PomodoroSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var phase: PomodoroPhase = .work
    var isPaused = false
    var deadline: Date?
    var remainingSeconds: TimeInterval
    var focusMinutes: Int
    var breakMinutes: Int
}

struct CompanionEvent: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var createdAt: Date
}

struct DailyProgress: Codable, Equatable {
    var day: String
    var todosCompleted = 0
    var focusMinutes = 0
    var habitCheckIns = 0
}

enum PetHomeItem: String, Codable, CaseIterable, Identifiable {
    case cushion, desk, lamp, blanket
    var id: String { rawValue }
    var title: String { switch self { case .cushion: return "软软坐垫"; case .desk: return "读书小桌"; case .lamp: return "暖光小灯"; case .blanket: return "小窝毛毯" } }
    var emoji: String { switch self { case .cushion: return "☁️"; case .desk: return "📚"; case .lamp: return "💡"; case .blanket: return "🧺" } }
}

enum PetAccessory: String, Codable, CaseIterable, Identifiable {
    case bow, scarf, sleepCap, blanket
    var id: String { rawValue }
    var title: String { switch self { case .bow: return "蝴蝶结"; case .scarf: return "软围巾"; case .sleepCap: return "晚安睡帽"; case .blanket: return "随身小毯" } }
    var emoji: String { switch self { case .bow: return "🎀"; case .scarf: return "🧣"; case .sleepCap: return "🌙"; case .blanket: return "🧶" } }
}

enum PetSeason: String, Codable, CaseIterable, Identifiable {
    case spring, summer, autumn, winter
    var id: String { rawValue }
    var title: String { switch self { case .spring: return "樱花春日"; case .summer: return "薄荷夏天"; case .autumn: return "栗子秋日"; case .winter: return "雪莓冬天" } }
    var emoji: String { switch self { case .spring: return "🌸"; case .summer: return "🍃"; case .autumn: return "🍂"; case .winter: return "❄️" } }
}

enum PetMood: String, CaseIterable {
    case calm, cheerful, sleepy, hungry, shy
    var title: String { switch self { case .calm: return "安心陪伴"; case .cheerful: return "心情晴朗"; case .sleepy: return "有一点困"; case .hungry: return "肚子空空"; case .shy: return "有点害羞" } }
    var emoji: String { switch self { case .calm: return "💜"; case .cheerful: return "✨"; case .sleepy: return "💤"; case .hungry: return "🍙"; case .shy: return "🌷" } }
}

enum PetGameKind: String, Codable, CaseIterable, Identifiable {
    case stars, hands, cookie
    var id: String { rawValue }
    var title: String { switch self { case .stars: return "接星星"; case .hands: return "猜猜哪只手"; case .cookie: return "找找小饼干" } }
    var emoji: String { switch self { case .stars: return "⭐️"; case .hands: return "🙌"; case .cookie: return "🍪" } }
    var maximumScore: Int { 1000 }
}

struct PetLife: Codable, Equatable {
    var homeItems: Set<PetHomeItem> = [.cushion, .desk, .lamp, .blanket]
    var accessories: Set<PetAccessory> = [.bow]
    var season: PetSeason = .autumn
    var contentment: Double = 65
    var shyUntil: Date?
    var foodServings: [String: Int] = [:]
    var gameBestScores: [String: Int] = [:]
    var gamePlayCounts: [String: Int] = [:]
    var gameRewardDays: [String: String] = [:]
}

struct CompanionState: Codable, Equatable {
    var version = 1
    var todos: [TodoItem] = []
    var notes: [NoteItem] = []
    var habits: [HabitItem] = []
    var shortcuts: [ShortcutItem] = []
    var stats: PetStats
    var settings = CompanionSettings()
    var life = PetLife()
    var pomodoro: PomodoroSession?
    var events: [CompanionEvent] = []
    var dailyProgress: [String: DailyProgress] = [:]
    var rewardedSessionIDs: [UUID] = []
    var rewardedFileJobIDs: [UUID] = []
    var lastGreetingDay: String?
    var lastAmbientAt: Date
    var lastRestReminderAt: Date

    init(now: Date) {
        stats = PetStats(lastUpdatedAt: now)
        lastAmbientAt = now
        lastRestReminderAt = now
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var notifySystem = false
    var codexTaskEvent = false
}

enum CodexTurnResult { case completed, failed }

struct AnimationRequest: Identifiable, Equatable {
    let id = UUID()
    let state: String
    let duration: Double
}

enum InteractionKind: String, CaseIterable {
    case pet, feed, play, rest
    var cooldown: TimeInterval {
        switch self {
        case .pet: return 8
        case .feed: return 300
        case .play: return 60
        case .rest: return 120
        }
    }
}

enum PetFoodCategory: String, CaseIterable, Identifiable {
    case meal, snack, drink
    var id: String { rawValue }
    var title: String {
        switch self {
        case .meal: return "主食"
        case .snack: return "小点心"
        case .drink: return "饮品"
        }
    }
}

enum PetFood: String, Codable, CaseIterable, Identifiable {
    case riceBall, sandwich, apple, cookie, cake, milk, water, herbalTea
    var id: String { rawValue }
    var title: String {
        switch self {
        case .riceBall: return "饭团"
        case .sandwich: return "三明治"
        case .apple: return "苹果块"
        case .cookie: return "小饼干"
        case .cake: return "草莓蛋糕"
        case .milk: return "温牛奶"
        case .water: return "温水"
        case .herbalTea: return "花草茶"
        }
    }
    var emoji: String {
        switch self {
        case .riceBall: return "🍙"
        case .sandwich: return "🥪"
        case .apple: return "🍎"
        case .cookie: return "🍪"
        case .cake: return "🍰"
        case .milk: return "🥛"
        case .water: return "💧"
        case .herbalTea: return "🍵"
        }
    }
    var detail: String {
        switch self {
        case .riceBall: return "软软的一小份，填饱肚子再忙。"
        case .sandwich: return "忙了一阵后，补充一份扎实的能量。"
        case .apple: return "切成小块，清脆又方便入口。"
        case .cookie: return "一块酥酥的小点心，分享片刻开心。"
        case .cake: return "甜甜的草莓味，庆祝今天的小进步。"
        case .milk: return "捧着暖暖的杯子，慢慢恢复精神。"
        case .water: return "喝一小口，也提醒自己喝点水。"
        case .herbalTea: return "闻闻淡淡的花香，一起缓口气。"
        }
    }
    var category: PetFoodCategory {
        switch self {
        case .riceBall, .sandwich: return .meal
        case .apple, .cookie, .cake: return .snack
        case .milk, .water, .herbalTea: return .drink
        }
    }
    var hungerRelief: Double {
        switch self {
        case .riceBall: return 30
        case .sandwich: return 40
        case .apple: return 18
        case .cookie: return 12
        case .cake: return 20
        case .milk: return 10
        case .water, .herbalTea: return 0
        }
    }
    var energyGain: Double {
        switch self {
        case .riceBall: return 5
        case .sandwich, .herbalTea: return 8
        case .apple: return 6
        case .cookie, .water: return 3
        case .cake: return 4
        case .milk: return 12
        }
    }
    var affectionGain: Int { self == .water ? 1 : (self == .cookie ? 3 : (self == .cake ? 4 : 2)) }
    var experienceGain: Int { isLightDrink ? 0 : 1 }
    var isLightDrink: Bool { self == .water || self == .herbalTea }
    var effectDescription: String {
        var effects: [String] = []
        if hungerRelief > 0 { effects.append("饥饿 −\(Int(hungerRelief))") }
        effects.append("精力 +\(Int(energyGain))")
        effects.append("好感 +\(affectionGain)")
        if experienceGain > 0 { effects.append("经验 +\(experienceGain)") }
        return "最多 " + effects.joined(separator: " · ")
    }
    fileprivate var response: String {
        switch self {
        case .riceBall: return "谢谢投喂，软软的饭团真香。你也要好好吃饭。"
        case .sandwich: return "谢谢投喂，三明治吃好啦，又有精神陪你了。"
        case .apple: return "谢谢投喂，苹果块脆脆的，一口刚刚好。"
        case .cookie: return "谢谢投喂，咔嚓！这块小饼干真让人开心。"
        case .cake: return "谢谢投喂，草莓蛋糕好甜，今天的小进步也值得庆祝。"
        case .milk: return "谢谢投喂，温牛奶喝完啦，手心也暖暖的。"
        case .water: return "咕嘟，喝好啦。你也喝一口水吧。"
        case .herbalTea: return "花草茶香香的，我们一起缓口气。"
        }
    }
}

enum PetUnlock: String, CaseIterable, Identifiable {
    case greeting, welcomeCelebration, encouragement, secretLine
    var id: String { rawValue }
    var title: String {
        switch self {
        case .greeting: return "温柔问候"
        case .welcomeCelebration: return "庆祝小进步"
        case .encouragement: return "专属鼓励"
        case .secretLine: return "悄悄话"
        }
    }
    var requiredLevel: Int {
        switch self {
        case .greeting: return 1
        case .welcomeCelebration: return 2
        case .encouragement: return 3
        case .secretLine: return 4
        }
    }
}

/// Local, persisted companion logic. All wall-clock calculations use the injected clock.
@MainActor final class CompanionStore: ObservableObject {
    @Published private(set) var state: CompanionState
    @Published private(set) var toast: ToastMessage?
    @Published private(set) var animationRequest: AnimationRequest?
    @Published private(set) var persistenceError: String?
    @Published private(set) var pomodoroRemainingSeconds: TimeInterval = 0
    @Published private(set) var companionWorking = false

    let directory: URL
    var saveURL: URL { directory.appendingPathComponent("companion-state.json") }
    private let now: () -> Date
    private let calendar: Calendar
    private var toastQueue: [ToastMessage] = []
    private var lastSavedState: CompanionState?
    private var lastStatsSaveAt: Date
    private var savingBlocked = false
    private let backupFile: (URL, URL) throws -> Void
    private var recentTouches: [Date] = []
    private var lastDodgeAt = Date.distantPast
    private struct GameSession {
        let id: UUID
        let kind: PetGameKind
        var activeSeconds: TimeInterval = 0
        var resumedAt: Date?
    }
    private var gameSession: GameSession?

    init(directory: URL, now: @escaping () -> Date = Date.init, calendar: Calendar = .current,
         backupFile: @escaping (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) }) {
        self.directory = directory
        self.now = now
        self.calendar = calendar
        self.backupFile = backupFile
        let current = now()
        self.state = CompanionState(now: current)
        self.lastStatsSaveAt = current
        let url = directory.appendingPathComponent("companion-state.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    state = try Self.decodeState(Data(contentsOf: url))
                    try Self.validateLoadedState(state)
                    lastSavedState = state
                } catch {
                    let backup = directory.appendingPathComponent("companion-state.corrupt-\(UUID().uuidString).json")
                    do {
                        try backupFile(url, backup)
                        persistenceError = "存档无法读取，原文件已保留为 \(backup.lastPathComponent)。已建立新存档。"
                    } catch {
                        // Never overwrite an unreadable file unless the original was preserved.
                        persistenceError = "存档无法读取且备份失败：\(error.localizedDescription)。原文件保留，本次无法保存。"
                        savingBlocked = true
                        lastSavedState = state
                        return
                    }
                }
            }
        } catch {
            persistenceError = "无法打开数据目录：\(error.localizedDescription)"
        }
        tick()
        persist()
    }

    var todayProgress: DailyProgress {
        let day = dayKey(now())
        return state.dailyProgress[day] ?? DailyProgress(day: day)
    }

    var companionName: String { state.settings.appearance.title }
    var companionShortName: String { state.settings.appearance.shortName }

    func addTodo(title: String, details: String = "", dueAt: Date? = nil) -> UUID {
        let item = TodoItem(title: cleanTitle(title, fallback: "新待办"), details: details, dueAt: dueAt, createdAt: now())
        state.todos.append(item)
        record("添加待办：\(item.title)")
        persist()
        return item.id
    }

    func updateTodo(id: UUID, title: String, details: String = "", dueAt: Date? = nil) {
        guard let i = state.todos.firstIndex(where: { $0.id == id }) else { return }
        if state.todos[i].dueAt != dueAt { state.todos[i].dueReminderSent = false }
        state.todos[i].title = cleanTitle(title, fallback: "待办")
        state.todos[i].details = details
        state.todos[i].dueAt = dueAt
        persist()
    }

    func deleteTodo(id: UUID) {
        state.todos.removeAll { $0.id == id }
        persist()
    }

    func setTodoCompleted(id: UUID, completed: Bool) {
        guard let i = state.todos.firstIndex(where: { $0.id == id }), state.todos[i].isCompleted != completed else { return }
        state.todos[i].isCompleted = completed
        if completed {
            if !state.todos[i].rewardGranted {
                state.todos[i].rewardGranted = true
                reward(experience: 15, affection: 3)
                updateProgress { $0.todosCompleted += 1 }
            }
            record("完成待办：\(state.todos[i].title)")
            emit("又完成一件事，\(state.settings.nickname)，做得很好。", animation: "celebrating", bypassQuiet: true)
        }
        persist()
    }

    func addNote(title: String, text: String = "") -> UUID {
        let item = NoteItem(title: cleanTitle(title, fallback: "便签"), text: text, updatedAt: now())
        state.notes.append(item)
        persist()
        return item.id
    }

    func updateNote(id: UUID, title: String, text: String) {
        guard let i = state.notes.firstIndex(where: { $0.id == id }) else { return }
        state.notes[i].title = cleanTitle(title, fallback: "便签")
        state.notes[i].text = text
        state.notes[i].updatedAt = now()
        persist()
    }

    func deleteNote(id: UUID) { state.notes.removeAll { $0.id == id }; persist() }

    func toggleNotePinned(id: UUID) {
        guard let i = state.notes.firstIndex(where: { $0.id == id }) else { return }
        state.notes[i].isPinned.toggle()
        state.notes[i].updatedAt = now()
        persist()
    }

    func addHabit(title: String) -> UUID {
        let item = HabitItem(title: cleanTitle(title, fallback: "每日习惯"))
        state.habits.append(item)
        persist()
        return item.id
    }

    func updateHabit(id: UUID, title: String) {
        guard let i = state.habits.firstIndex(where: { $0.id == id }) else { return }
        state.habits[i].title = cleanTitle(title, fallback: "每日习惯")
        persist()
    }

    func deleteHabit(id: UUID) { state.habits.removeAll { $0.id == id }; persist() }

    func isHabitCheckedInToday(_ habit: HabitItem) -> Bool { habit.checkIns.contains(dayKey(now())) }

    @discardableResult func checkInHabit(id: UUID) -> Bool {
        guard let i = state.habits.firstIndex(where: { $0.id == id }) else { return false }
        let day = dayKey(now())
        guard !state.habits[i].checkIns.contains(day) else { return false }
        state.habits[i].checkIns.append(day)
        reward(experience: 5, affection: 1)
        updateProgress { $0.habitCheckIns += 1 }
        record("习惯打卡：\(state.habits[i].title)")
        emit("今天也坚持了，慢慢来，我陪着你。", animation: "waving", bypassQuiet: true)
        persist()
        return true
    }

    func addShortcut(label: String, path: String) -> UUID {
        let item = ShortcutItem(label: cleanTitle(label, fallback: "快捷入口"), path: path)
        state.shortcuts.append(item)
        persist()
        return item.id
    }

    func updateShortcut(id: UUID, label: String, path: String) {
        guard let i = state.shortcuts.firstIndex(where: { $0.id == id }) else { return }
        state.shortcuts[i].label = cleanTitle(label, fallback: "快捷入口")
        state.shortcuts[i].path = path
        persist()
    }

    func deleteShortcut(id: UUID) { state.shortcuts.removeAll { $0.id == id }; persist() }

    func startPomodoro(minutes: Int, breakMinutes: Int = 5) {
        settlePomodoro(at: now())
        let focus = min(240, max(1, minutes))
        let rest = min(60, max(1, breakMinutes))
        state.pomodoro = PomodoroSession(deadline: now().addingTimeInterval(Double(focus * 60)), remainingSeconds: Double(focus * 60), focusMinutes: focus, breakMinutes: rest)
        pomodoroRemainingSeconds = Double(focus * 60)
        record("开始 \(focus) 分钟专注")
        emit("安心做事吧，这段时间我会安静陪着。", animation: "idle", bypassQuiet: true)
        persist()
    }

    func pausePomodoro() {
        settlePomodoro(at: now())
        guard var session = state.pomodoro, !session.isPaused, let deadline = session.deadline else {
            persist()
            return
        }
        session.remainingSeconds = max(0, deadline.timeIntervalSince(now()))
        session.deadline = nil
        session.isPaused = true
        state.pomodoro = session
        pomodoroRemainingSeconds = session.remainingSeconds
        persist()
    }

    func resumePomodoro() {
        guard var session = state.pomodoro, session.isPaused else { return }
        session.deadline = now().addingTimeInterval(session.remainingSeconds)
        session.isPaused = false
        state.pomodoro = session
        pomodoroRemainingSeconds = session.remainingSeconds
        persist()
    }

    func cancelPomodoro() {
        guard state.pomodoro != nil else { return }
        state.pomodoro = nil
        pomodoroRemainingSeconds = 0
        record("取消本轮专注")
        persist()
    }

    func interactionCooldownRemaining(_ kind: InteractionKind) -> TimeInterval {
        guard let previous = state.stats.interactionDates[kind.rawValue] else { return 0 }
        return max(0, kind.cooldown - now().timeIntervalSince(previous))
    }

    var satiety: Int { Int(min(100, max(0, 100 - state.stats.hunger)).rounded()) }

    var appetiteDescription: String {
        switch state.stats.hunger {
        case ..<10: return "肚子还饱着，先陪我消消食吧。"
        case ..<35: return "有一点点饿，小份点心就很好。"
        case ..<70: return "肚子有点空，来一份主食吧。"
        default: return "肚子咕咕叫啦，想好好吃一顿。"
        }
    }

    var feedingHistory: [CompanionEvent] {
        Array(state.events.reversed().lazy.filter { $0.text.hasPrefix("喂养：") }.prefix(6))
    }

    var petMood: PetMood {
        if let until = state.life.shyUntil, now() < until { return .shy }
        if state.stats.energy < 25 { return .sleepy }
        if state.stats.hunger > 70 { return .hungry }
        return state.life.contentment >= 72 ? .cheerful : .calm
    }

    var moodDescription: String {
        switch petMood {
        case .calm: return "有你在旁边，安安静静也很好。"
        case .cheerful: return "刚刚的小小关心，让今天亮了一点。"
        case .sleepy: return "眼皮有点沉，想低下头靠着坐垫歇会儿。"
        case .hungry: return "肚子咕咕叫，想和你分享一点吃的。"
        case .shy: return "摸得有点密啦，轻轻躲一下，等一会儿再来。"
        }
    }

    var favoriteFood: PetFood {
        // A stable initial preference gradually learns from shared meals.
        let seeds: [PetFood: Int] = [.cookie: 3, .cake: 2, .milk: 1]
        return PetFood.allCases.max { lhs, rhs in
            let left = (seeds[lhs] ?? 0) + (state.life.foodServings[lhs.rawValue] ?? 0) / 3
            let right = (seeds[rhs] ?? 0) + (state.life.foodServings[rhs.rawValue] ?? 0) / 3
            if left == right { return lhs.rawValue > rhs.rawValue }
            return left < right
        } ?? .cookie
    }

    func foodPreference(_ food: PetFood) -> String {
        if food == favoriteFood { return "最喜欢 · 看到就开心" }
        let count = state.life.foodServings[food.rawValue] ?? 0
        if count >= 3 { return "熟悉的味道 · 已分享 \(count) 次" }
        if count > 0 { return "尝过啦 · 已分享 \(count) 次" }
        return "还想和你一起尝尝"
    }

    var contextualWish: String {
        if companionWorking { return "我翻着书陪你，等忙完再一起玩。" }
        if petMood == .shy { return "先给我一点点空间，马上就好。" }
        if state.stats.energy < 25 { return "想戴上睡帽，裹着小毯子打个盹。" }
        if state.stats.hunger > 70 { return "想吃一份软软的饭团，再喝一口水。" }
        if state.stats.hunger < 10 { return "吃饱啦，想整理一下头发、翻两页书。" }
        let hour = calendar.component(.hour, from: now())
        if hour >= 21 || hour < 7 { return "想把小灯调暖，低下头安安静静休息。" }
        if hour < 11 { return "想伸个懒腰，和你开始新的一天。" }
        if state.life.contentment >= 72 { return "想把好心情分给你，我们接一分钟星星吧。" }
        return "有一点想念\(favoriteFood.title)的味道。"
    }

    func setHomeItem(_ item: PetHomeItem, enabled: Bool) {
        if enabled { state.life.homeItems.insert(item) } else { state.life.homeItems.remove(item) }
        persist()
    }

    func setAccessory(_ accessory: PetAccessory, enabled: Bool) {
        if enabled { state.life.accessories.insert(accessory) } else { state.life.accessories.remove(accessory) }
        persist()
    }

    func setSeason(_ season: PetSeason) { state.life.season = season; persist() }

    func applySeasonalOutfit() {
        switch state.life.season {
        case .spring, .summer: state.life.accessories = [.bow]
        case .autumn: state.life.accessories = [.bow, .scarf]
        case .winter: state.life.accessories = [.scarf, .sleepCap, .blanket]
        }
        persist()
    }

    func performDailyAction(_ name: String) {
        guard ["rub-eyes", "stretch", "page-flip", "groom", "yawn"].contains(name) else { return }
        animationRequest = AnimationRequest(state: name, duration: 3)
    }

    func setCompanionWorking(_ working: Bool) {
        guard companionWorking != working else { return }
        if working, let session = gameSession { pauseGame(sessionID: session.id) }
        companionWorking = working
    }

    /// Visual touch feedback remains responsive; rewards still share the existing eight-second cooldown.
    @discardableResult func touchPet(zone: String) -> Bool {
        guard ["head", "face", "book"].contains(zone) else { return false }
        let current = now()
        updateStats(at: current)
        recentTouches.removeAll { current.timeIntervalSince($0) > 6 || current < $0 }
        recentTouches.append(current)
        if recentTouches.count >= 4 {
            state.life.shyUntil = current.addingTimeInterval(7)
            animationRequest = AnimationRequest(state: "dodge", duration: 1.8)
            if current.timeIntervalSince(lastDodgeAt) >= 5 {
                lastDodgeAt = current
                emit("嘿嘿，有一点痒。让我缓一小会儿。", animation: "dodge", bypassQuiet: true)
            }
            persist()
            return false
        }
        let rewarded = interactionCooldownRemaining(.pet) <= 0
        animationRequest = AnimationRequest(state: "touch-" + zone, duration: 2.5)
        if rewarded {
            state.stats.interactionDates[InteractionKind.pet.rawValue] = current
            state.life.shyUntil = nil
            state.life.contentment = min(100, state.life.contentment + 3)
            reward(experience: 1, affection: 1)
            let line = zone == "book" ? "这页很好看，想分给你一起读。" : (zone == "face" ? "脸颊暖暖的，谢谢你。" : "轻轻摸摸头，今天也辛苦了。")
            emit(line, animation: "touch-" + zone, bypassQuiet: true)
            record("轻轻摸了摸\(companionShortName)" + (zone == "book" ? "的书" : (zone == "face" ? "的脸颊" : "的头")))
            persist()
        }
        return rewarded
    }

    func gameBestScore(_ kind: PetGameKind) -> Int { state.life.gameBestScores[kind.rawValue] ?? 0 }
    func gameRewardAvailable(_ kind: PetGameKind) -> Bool { state.life.gameRewardDays[kind.rawValue] != dayKey(now()) }

    @discardableResult func beginGame(_ kind: PetGameKind) -> UUID {
        let id = UUID()
        gameSession = GameSession(id: id, kind: kind, resumedAt: companionWorking ? nil : now())
        return id
    }

    func pauseGame(sessionID: UUID) {
        guard var session = gameSession, session.id == sessionID, let started = session.resumedAt else { return }
        session.activeSeconds += max(0, now().timeIntervalSince(started))
        session.resumedAt = nil
        gameSession = session
    }

    @discardableResult func resumeGame(sessionID: UUID) -> Bool {
        guard !companionWorking, var session = gameSession, session.id == sessionID else { return false }
        if session.resumedAt != nil { return true }
        session.resumedAt = now()
        gameSession = session
        return true
    }

    func cancelGame(sessionID: UUID) {
        if gameSession?.id == sessionID { gameSession = nil }
    }

    /// Only a completed, active one-minute session can update records. Each game rewards once per day.
    @discardableResult func recordGameResult(kind: PetGameKind, score: Int, sessionID: UUID) -> Bool {
        guard let session = gameSession, session.id == sessionID, session.kind == kind,
              (0...kind.maximumScore).contains(score) else { return false }
        let elapsed = session.activeSeconds + (session.resumedAt.map { max(0, now().timeIntervalSince($0)) } ?? 0)
        guard elapsed >= 59.5 else { return false }
        gameSession = nil
        state.life.gameBestScores[kind.rawValue] = max(gameBestScore(kind), score)
        state.life.gamePlayCounts[kind.rawValue] = min(1_000_000, (state.life.gamePlayCounts[kind.rawValue] ?? 0) + 1)
        let rewarded = score > 0 && gameRewardAvailable(kind)
        if rewarded {
            state.life.gameRewardDays[kind.rawValue] = dayKey(now())
            state.life.contentment = min(100, state.life.contentment + 5)
            reward(experience: 2, affection: 1)
        }
        let suffix = rewarded ? " · 今日首次完成，好感 +1 / 经验 +2" : " · 记录已保存"
        record("游乐角：\(kind.title) \(score) 分" + suffix)
        if !companionWorking { emit("一起玩得很开心！\(kind.title)获得 \(score) 分。", animation: "celebrating", bypassQuiet: true) }
        persist()
        return true
    }

    func feedingCooldownRemaining(_ food: PetFood) -> TimeInterval {
        let key = food.isLightDrink ? "drink" : InteractionKind.feed.rawValue
        guard let previous = state.stats.interactionDates[key] else { return 0 }
        return max(0, (food.isLightDrink ? 120 : InteractionKind.feed.cooldown) - now().timeIntervalSince(previous))
    }

    func feedingBlockReason(_ food: PetFood) -> String? {
        let remaining = Int(ceil(feedingCooldownRemaining(food)))
        if remaining > 0 { return String(format: "再等 %d:%02d", remaining / 60, remaining % 60) }
        if !food.isLightDrink && state.stats.hunger < 10 { return "还饱着，先消消食" }
        return nil
    }

    @discardableResult func feed(_ food: PetFood) -> Bool {
        let current = now()
        updateStats(at: current)
        if let reason = feedingBlockReason(food) {
            emit("\(reason)。\(food.isLightDrink ? "小口慢慢喝就好。" : "等肚子准备好了再吃吧。")", animation: "waving", bypassQuiet: true)
            return false
        }
        let before = state.stats
        state.stats.interactionDates[food.isLightDrink ? "drink" : InteractionKind.feed.rawValue] = current
        state.stats.hunger = max(0, state.stats.hunger - food.hungerRelief)
        state.stats.energy = min(100, state.stats.energy + food.energyGain)
        let isFavorite = food == favoriteFood
        state.life.foodServings[food.rawValue] = min(1_000_000, (state.life.foodServings[food.rawValue] ?? 0) + 1)
        state.life.contentment = min(100, state.life.contentment + (isFavorite ? 10 : 6))
        state.life.shyUntil = nil
        reward(experience: food.experienceGain, affection: food.affectionGain)
        func quantity(_ value: Double) -> String {
            abs(value.rounded() - value) < 0.0001 ? String(Int(value.rounded())) : String(format: "%.1f", value)
        }
        var effects: [String] = []
        let hungerDelta = before.hunger - state.stats.hunger
        let energyDelta = state.stats.energy - before.energy
        if hungerDelta > 0 { effects.append("饥饿 −\(quantity(hungerDelta))") }
        if energyDelta > 0 { effects.append("精力 +\(quantity(energyDelta))") }
        let affectionDelta = state.stats.affection - before.affection
        if affectionDelta > 0 { effects.append("好感 +\(affectionDelta)") }
        let experienceDelta = state.stats.experience - before.experience
        if experienceDelta > 0 { effects.append("经验 +\(experienceDelta)") }
        let result = effects.isEmpty ? "现在状态很充足。" : effects.joined(separator: " · ")
        let foodAnimation = (food.category == .drink ? "drink-" : "eat-") + food.rawValue
        emit(food.response + (isFavorite ? " 是我喜欢的味道！" : "") + "\n" + result, animation: foodAnimation, bypassQuiet: true)
        record("喂养：\(food.title) · \(result)", at: current)
        persist()
        return true
    }

    @discardableResult func interact(_ kind: InteractionKind) -> Bool {
        if kind == .feed { return feed(.riceBall) }
        if kind == .pet { return touchPet(zone: "head") }
        updateStats(at: now())
        guard interactionCooldownRemaining(kind) <= 0 else {
            emit("刚刚已经收到啦，稍等一小会儿。", animation: "waving", bypassQuiet: true)
            return false
        }
        state.stats.interactionDates[kind.rawValue] = now()
        switch kind {
        case .pet:
            reward(experience: 1, affection: 1)
            emit("嗯，谢谢你。今天也辛苦了。", animation: "waving", bypassQuiet: true)
            record("轻轻摸了摸\(companionShortName)")
        case .feed:
            break // Routed through the shared feeding rules above.
        case .play:
            state.stats.energy = max(0, state.stats.energy - 12)
            state.stats.hunger = min(100, state.stats.hunger + 6)
            reward(experience: 2, affection: 2)
            emit("陪你放松一会儿。然后一起继续努力。", animation: "jumping", bypassQuiet: true)
            record("和\(companionShortName)一起玩耍")
        case .rest:
            state.stats.energy = min(100, state.stats.energy + 20)
            state.lastRestReminderAt = now()
            reward(experience: 0, affection: 1)
            emit("好，我们都歇一歇。", animation: "sleeping", bypassQuiet: true)
            record("陪\(companionShortName)休息")
        }
        persist()
        return true
    }

    @discardableResult func registerFileSuccess(jobID: UUID) -> Bool {
        guard !state.rewardedFileJobIDs.contains(jobID) else { return false }
        state.rewardedFileJobIDs.append(jobID)
        reward(experience: 3, affection: 1)
        record("完成一次文件处理")
        emit("文件已经处理好了，一起收好吧。", animation: "review", bypassQuiet: true)
        persist()
        return true
    }

    @discardableResult func performUnlockedAction(_ action: PetUnlock) -> Bool {
        guard state.stats.level >= action.requiredLevel else {
            emit("这个互动还没有解锁，一起积攒些小进步吧。", animation: "waving", bypassQuiet: true)
            return false
        }
        let nickname = state.settings.nickname
        switch action {
        case .greeting:
            emit("\(nickname)，见到你真好。今天想先做什么？", animation: "waving", bypassQuiet: true)
        case .welcomeCelebration:
            emit("每一点进步都值得庆祝。为你开心。", animation: "celebrating", bypassQuiet: true)
        case .encouragement:
            emit("\(nickname)，暂时做不到也没关系。我们可以把它拆成小小的一步。", animation: "waving", bypassQuiet: true)
        case .secretLine:
            emit("悄悄告诉你：陪你慢慢把日子过好，就是我喜欢做的事。", animation: "waving", bypassQuiet: true)
        }
        record("互动动作：\(action.title)")
        persist()
        return true
    }

    func updateSettings(_ settings: CompanionSettings) {
        var validated = settings
        validated.nickname = cleanTitle(settings.nickname, fallback: "你")
        validated.scale = min(1.8, max(0.6, settings.scale.isFinite ? settings.scale : 1))
        validated.interactionFrequency = min(1, max(0, settings.interactionFrequency.isFinite ? settings.interactionFrequency : 0.35))
        validated.quietStartHour = min(23, max(0, settings.quietStartHour))
        validated.quietEndHour = min(23, max(0, settings.quietEndHour))
        validated.restReminderMinutes = min(240, max(0, settings.restReminderMinutes))
        if let x = validated.petX, !x.isFinite { validated.petX = nil }
        if let y = validated.petY, !y.isFinite { validated.petY = nil }
        guard validated != state.settings else { return }
        state.settings = validated
        persist()
    }

    func isQuietTime(at date: Date? = nil, settings: CompanionSettings? = nil) -> Bool {
        let s = settings ?? state.settings
        guard s.doNotDisturbEnabled else { return false }
        let hour = calendar.component(.hour, from: date ?? now())
        if s.quietStartHour == s.quietEndHour { return true }
        if s.quietStartHour < s.quietEndHour { return hour >= s.quietStartHour && hour < s.quietEndHour }
        return hour >= s.quietStartHour || hour < s.quietEndHour
    }

    /// Called by the app's timer. Countdown values are derived from deadlines, not tick counts.
    func tick() {
        let current = now()
        let before = state
        updateStats(at: current)
        settlePomodoro(at: current)
        if state.settings.remindersEnabled && !isQuietTime(at: current) {
            let due = state.todos.indices.filter { !state.todos[$0].isCompleted && !state.todos[$0].dueReminderSent && (state.todos[$0].dueAt.map { $0 <= current } ?? false) }
            if !due.isEmpty {
                let titles = due.map { state.todos[$0].title }
                for i in due { state.todos[i].dueReminderSent = true }
                let label = titles.count == 1 ? titles[0] : "\(titles[0]) 等 \(titles.count) 件待办"
                record("截止提醒：\(label)")
                emit("\(label) 到时间了，方便时看一下吧。", animation: "waiting", notifySystem: true)
            }
            if state.settings.restReminderMinutes > 0 && current.timeIntervalSince(state.lastRestReminderAt) >= Double(state.settings.restReminderMinutes * 60) {
                state.lastRestReminderAt = current
                record("休息提醒")
                emit("坐久了，喝口水、看看远处吧。", animation: "waving", notifySystem: true)
            }
        }
        ambient(at: current)
        // Statistics decay is visible each tick; only flush its passive changes once a minute.
        let substantialChange = before.todos != state.todos || before.pomodoro != state.pomodoro || before.events != state.events || before.lastGreetingDay != state.lastGreetingDay || before.lastAmbientAt != state.lastAmbientAt || before.dailyProgress != state.dailyProgress
        if substantialChange || current.timeIntervalSince(lastStatsSaveAt) >= 60 {
            persist()
            lastStatsSaveAt = current
        }
    }

    func dismissToast() {
        while !toastQueue.isEmpty {
            let next = toastQueue.removeFirst()
            // Quiet hours or a disabled reminder switch may have begun while
            // this automatic reminder waited behind another bubble.
            if next.notifySystem && (!state.settings.remindersEnabled || isQuietTime()) { continue }
            if next.codexTaskEvent && !state.settings.codexTaskReminders { continue }
            toast = next
            return
        }
        toast = nil
    }

    /// One Codex turn ended. This does not imply that its tests passed or award game progress.
    func notifyCodexTurnEnded(_ result: CodexTurnResult) {
        guard state.settings.codexTaskReminders else { return }
        let text = result == .completed
            ? "Agent 这一轮已结束，可以去查看结果了。"
            : "Agent 这一轮遇到了错误，方便时看一下吧。"
        if emit(text, animation: result == .completed ? "review" : "failed", notifySystem: true, codexTaskEvent: true) {
            record(result == .completed ? "Agent 本轮结束" : "Agent 本轮出错")
            persist()
        }
    }

    func save() { persist() }

    /// Export the current state without changing the active save or its backup protection.
    func exportState(to url: URL) throws {
        guard url.standardizedFileURL != saveURL.standardizedFileURL else {
            throw NSError(domain: "CompanionStore", code: 3, userInfo: [NSLocalizedDescriptionKey: "请导出到另外一个文件，避免覆盖当前存档"])
        }
        try encodedState(state).write(to: url, options: [.atomic])
    }

    /// Validate first, preserve the current bytes, then replace the disk and memory together.
    func importState(from url: URL) throws {
        let imported = try Self.decodeState(Data(contentsOf: url))
        try Self.validateLoadedState(imported)
        let data = try encodedState(imported)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: saveURL.path) {
            let backup = directory.appendingPathComponent("companion-state.before-import-\(UUID().uuidString).json")
            try backupFile(saveURL, backup)
        }
        try data.write(to: saveURL, options: [.atomic])
        state = imported
        lastSavedState = imported
        savingBlocked = false
        persistenceError = nil
        toast = nil
        toastQueue.removeAll()
        gameSession = nil
        recentTouches.removeAll()
        tick()
    }

    private func settlePomodoro(at current: Date) {
        guard var session = state.pomodoro else { pomodoroRemainingSeconds = 0; return }
        if session.isPaused { pomodoroRemainingSeconds = session.remainingSeconds; return }
        guard let deadline = session.deadline else { return }
        if current < deadline {
            pomodoroRemainingSeconds = max(0, deadline.timeIntervalSince(current))
            return
        }
        if session.phase == .work {
            if !state.rewardedSessionIDs.contains(session.id) {
                state.rewardedSessionIDs.append(session.id)
                reward(experience: 10, affection: 2)
                updateProgress(at: deadline) { $0.focusMinutes += session.focusMinutes }
                record("完成 \(session.focusMinutes) 分钟专注", at: deadline)
                emit("这一轮完成了，做得很好。接下来休息 \(session.breakMinutes) 分钟。", animation: "celebrating", notifySystem: true)
            }
            session.phase = .rest
            session.remainingSeconds = Double(session.breakMinutes * 60)
            session.deadline = deadline.addingTimeInterval(session.remainingSeconds)
            state.lastRestReminderAt = current
            state.pomodoro = session
        }
        if let restDeadline = session.deadline, current >= restDeadline {
            state.pomodoro = nil
            pomodoroRemainingSeconds = 0
            record("本轮休息结束", at: restDeadline)
            emit("休息时间结束了，准备好了再开始下一轮。", animation: "review", notifySystem: true)
        } else {
            pomodoroRemainingSeconds = max(0, session.deadline!.timeIntervalSince(current))
        }
    }

    private func updateStats(at current: Date) {
        let elapsed = current.timeIntervalSince(state.stats.lastUpdatedAt)
        guard elapsed > 0 else { return }
        state.stats.hunger = min(100, state.stats.hunger + elapsed / 3600 * 5)
        state.stats.energy = max(0, state.stats.energy - elapsed / 3600 * 3)
        // Contentment returns gently toward a calm baseline, never punishing time away.
        if state.life.contentment > 55 { state.life.contentment = max(55, state.life.contentment - elapsed / 3600 * 2) }
        state.stats.lastUpdatedAt = current
    }

    private func ambient(at current: Date) {
        let settings = state.settings
        guard settings.remindersEnabled, settings.interactionFrequency > 0, !isQuietTime(at: current), !companionWorking else { return }
        // A running focus period suppresses unsolicited companionship dialogue.
        if let session = state.pomodoro, session.phase == .work && !session.isPaused { return }
        let day = dayKey(current)
        if state.lastGreetingDay != day {
            state.lastGreetingDay = day
            state.lastAmbientAt = current
            let hour = calendar.component(.hour, from: current)
            let greeting = hour < 12 ? "早安" : (hour < 18 ? "下午好" : "晚上好")
            emit("\(greeting)，\(settings.nickname)。今天也一起慢慢做好想做的事。", animation: "waving")
            return
        }
        let interval = 3600 - settings.interactionFrequency * 2700
        guard current.timeIntervalSince(state.lastAmbientAt) >= interval else { return }
        state.lastAmbientAt = current
        let line = contextualWish
        emit(line, animation: state.stats.energy < 25 ? "sleeping" : "waving")
    }

    @discardableResult private func emit(_ text: String, animation: String, bypassQuiet: Bool = false, notifySystem: Bool = false, codexTaskEvent: Bool = false) -> Bool {
        guard bypassQuiet || (state.settings.remindersEnabled && !isQuietTime()) else { return false }
        let message = ToastMessage(text: text, notifySystem: notifySystem, codexTaskEvent: codexTaskEvent)
        if toast == nil { toast = message }
        else if toastQueue.count < 30 { toastQueue.append(message) }
        let duration: Double = animation == "sleeping" ? 12 : ((animation.hasPrefix("eat-") || animation.hasPrefix("drink-")) ? 6.5 : 4)
        animationRequest = AnimationRequest(state: animation, duration: duration)
        return true
    }

    private func reward(experience: Int, affection: Int) {
        state.stats.experience += experience
        state.stats.affection = min(100, max(0, state.stats.affection + affection))
    }

    private func updateProgress(at date: Date? = nil, _ mutate: (inout DailyProgress) -> Void) {
        let day = dayKey(date ?? now())
        var progress = state.dailyProgress[day] ?? DailyProgress(day: day)
        mutate(&progress)
        state.dailyProgress[day] = progress
        if state.dailyProgress.count > 120 {
            for key in state.dailyProgress.keys.sorted().prefix(state.dailyProgress.count - 120) { state.dailyProgress.removeValue(forKey: key) }
        }
    }

    private func record(_ text: String, at date: Date? = nil) {
        state.events.append(CompanionEvent(text: text, createdAt: date ?? now()))
        if state.events.count > 200 { state.events.removeFirst(state.events.count - 200) }
    }

    private func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func cleanTitle(_ value: String, fallback: String) -> String {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? fallback : String(result.prefix(200))
    }

    private func persist() {
        guard !savingBlocked, state != lastSavedState else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encodedState(state).write(to: saveURL, options: [.atomic])
            lastSavedState = state
        } catch {
            persistenceError = "存档保存失败：\(error.localizedDescription)。请确认数据目录可写。"
        }
    }

    private func encodedState(_ value: CompanionState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    /// Optional additions retain version 1's prior save format.
    /// Fill only absent fields; malformed or unknown supplied values still fail validation.
    private static func decodeState(_ data: Data) throws -> CompanionState {
        var source = data
        if var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           var settings = object["settings"] as? [String: Any] {
            var migrated = false
            if settings["hardwareHover"] == nil { settings["hardwareHover"] = true; migrated = true }
            if settings["appearance"] == nil { settings["appearance"] = PetAppearance.whiteDragon.rawValue; migrated = true }
            if settings["codexTaskReminders"] == nil { settings["codexTaskReminders"] = true; migrated = true }
            if settings["codexProgressBubble"] == nil { settings["codexProgressBubble"] = true; migrated = true }
            let lifeDefaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PetLife())) as! [String: Any]
            if object["life"] == nil {
                object["life"] = lifeDefaults
                migrated = true
            } else if var life = object["life"] as? [String: Any] {
                for (key, value) in lifeDefaults where life[key] == nil { life[key] = value; migrated = true }
                object["life"] = life
            }
            if migrated {
                object["settings"] = settings
                source = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            }
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(CompanionState.self, from: source)
    }

    private static func validateLoadedState(_ state: CompanionState) throws {
        guard state.version == 1,
              (0...1_000_000_000).contains(state.stats.experience),
              (0...100).contains(state.stats.affection),
              state.stats.hunger.isFinite, state.stats.energy.isFinite,
              (0...100).contains(state.stats.hunger), (0...100).contains(state.stats.energy),
              state.stats.lastUpdatedAt.timeIntervalSince1970.isFinite,
              (0.6...1.8).contains(state.settings.scale), (0...1).contains(state.settings.interactionFrequency),
              (0...23).contains(state.settings.quietStartHour), (0...23).contains(state.settings.quietEndHour),
              (0...240).contains(state.settings.restReminderMinutes),
              state.settings.petX?.isFinite != false, state.settings.petY?.isFinite != false,
              state.life.contentment.isFinite, (0...100).contains(state.life.contentment),
              state.life.shyUntil?.timeIntervalSince1970.isFinite != false,
              state.life.foodServings.allSatisfy({ PetFood(rawValue: $0.key) != nil && (0...1_000_000).contains($0.value) }),
              state.life.gameBestScores.allSatisfy({ key, score in PetGameKind(rawValue: key).map { (0...$0.maximumScore).contains(score) } ?? false }),
              state.life.gamePlayCounts.allSatisfy({ PetGameKind(rawValue: $0.key) != nil && (0...1_000_000).contains($0.value) }),
              state.life.gameRewardDays.allSatisfy({ PetGameKind(rawValue: $0.key) != nil && $0.value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }),
              state.events.count <= 200,
              state.dailyProgress.values.allSatisfy({ (0...1_000_000_000).contains($0.todosCompleted) && (0...1_000_000_000).contains($0.focusMinutes) && (0...1_000_000_000).contains($0.habitCheckIns) }),
              state.todos.count == Set(state.todos.map(\.id)).count,
              state.notes.count == Set(state.notes.map(\.id)).count,
              state.habits.count == Set(state.habits.map(\.id)).count,
              state.shortcuts.count == Set(state.shortcuts.map(\.id)).count else {
            throw NSError(domain: "CompanionStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "存档数据不完整或格式不受支持"])
        }
        if let session = state.pomodoro {
            guard session.remainingSeconds.isFinite, session.remainingSeconds >= 0,
                  (1...240).contains(session.focusMinutes), (1...60).contains(session.breakMinutes),
                  session.isPaused ? session.deadline == nil : session.deadline != nil else {
                throw NSError(domain: "CompanionStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "专注计时数据无效"])
            }
        }
    }
}
