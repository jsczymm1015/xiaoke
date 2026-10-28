import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PanelActions {
    var showPet: () -> Void
    var chooseFile: () -> Void
    var addShortcut: () -> Void
    var openShortcut: (UUID) -> Void
    var exportData: () -> Void
    var importData: () -> Void
    var quit: () -> Void
}

private enum CompanionSection: String, CaseIterable, Identifiable {
    case today, focus, care, home, wardrobe, playroom, shortcuts, files, hardware, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "今日"
        case .focus: return "专注"
        case .care: return "陪伴与养成"
        case .home: return "温暖小窝"
        case .wardrobe: return "小小衣橱"
        case .playroom: return "游乐角"
        case .shortcuts: return "快捷入口"
        case .files: return "文件助手"
        case .hardware: return "硬件"
        case .settings: return "设置"
        }
    }
    var icon: String {
        switch self {
        case .today: return "sun.max"
        case .focus: return "timer"
        case .care: return "heart"
        case .home: return "house"
        case .wardrobe: return "tshirt"
        case .playroom: return "gamecontroller"
        case .shortcuts: return "square.grid.2x2"
        case .files: return "doc.text.magnifyingglass"
        case .hardware: return "gauge.with.dots.needle.50percent"
        case .settings: return "slider.horizontal.3"
        }
    }
    var subtitle: String {
        switch self {
        case .today: return "把今天的事，一件件轻轻完成。"
        case .focus: return "专注的时候，小可安静陪着你。"
        case .care: return "一点点相处，积累你们的默契。"
        case .home: return "坐垫、灯光和一本书，都是家的样子。"
        case .wardrobe: return "给今天添一点喜欢的颜色。"
        case .playroom: return "留一分钟，和小可一起收集小快乐。"
        case .shortcuts: return "常用的应用与文件，随手就能打开。"
        case .files: return "先看内容，再决定是否交给 Codex。"
        case .hardware: return "看看这台电脑此刻的状态。"
        case .settings: return "让小可按你舒服的节奏陪伴。"
        }
    }
}

enum CompanionTheme {
    static let background = Color(red: 0.988, green: 0.976, blue: 0.958)
    static let sidebar = Color(red: 0.950, green: 0.931, blue: 0.982)
    static let surface = Color.white
    static let surfaceRaised = Color(red: 0.968, green: 0.951, blue: 0.987)
    static let accent = Color(red: 0.475, green: 0.345, blue: 0.655)
    static let text = Color(red: 0.260, green: 0.225, blue: 0.315)
    static let secondary = Color(red: 0.465, green: 0.421, blue: 0.520)
    static let border = Color(red: 0.875, green: 0.839, blue: 0.915)
    static let warning = Color(red: 0.690, green: 0.360, blue: 0.190)
    static let lavender = Color(red: 0.920, green: 0.883, blue: 0.981)
    static let peach = Color(red: 0.995, green: 0.906, blue: 0.849)
    static let mint = Color(red: 0.866, green: 0.945, blue: 0.907)
}

/// Retain the shared shape API for the other panels while giving every surface soft corners.
struct CornerPanelShape: Shape {
    var cut: CGFloat = 10
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: min(22, cut + 8), style: .continuous).path(in: rect)
    }
}

struct HUDButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    init(prominent: Bool = false) { self.prominent = prominent }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(isEnabled ? (prominent ? Color.white : CompanionTheme.accent) : CompanionTheme.secondary)
            .padding(.horizontal, 15).padding(.vertical, 10)
            .background(isEnabled && prominent ? CompanionTheme.accent : CompanionTheme.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(prominent && isEnabled ? Color.clear : CompanionTheme.border.opacity(0.8), lineWidth: 1))
            .shadow(color: prominent && isEnabled ? CompanionTheme.accent.opacity(0.17) : .clear, radius: 6, y: 3)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct HUDFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(CompanionTheme.text)
            .padding(11)
            .background(CompanionTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CompanionTheme.border, lineWidth: 1))
    }
}

@MainActor
struct CompanionPanel: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject var assistant: FileAssistant
    @ObservedObject var hardware: HardwareMonitor
    @ObservedObject var codexMonitor: AgentTaskMonitor
    let actions: PanelActions
    @State private var section: CompanionSection = .today
    @StateObject private var playroomController = PetPlayroomController()
    @State private var todoDraft: TodoDraft?
    @State private var noteDraft: NoteDraft?
    @State private var habitDraft: HabitDraft?
    @State private var shortcutDraft: ShortcutDraft?
    @State private var habitTitle = ""
    @State private var focusMinutes = 25
    @State private var breakMinutes = 5
    @State private var fileDropTargeted = false
    @State private var foodCategory: PetFoodCategory = .meal
    @State private var careNavigationRevision = 0
    @State private var hardwareNavigationRevision = 0

    init(store: CompanionStore, assistant: FileAssistant, hardware: HardwareMonitor, codexMonitor: AgentTaskMonitor, actions: PanelActions) {
        self.store = store
        self.assistant = assistant
        self.hardware = hardware
        self.codexMonitor = codexMonitor
        self.actions = actions
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(CompanionTheme.border.opacity(0.45)).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                header
                if let error = store.persistenceError {
                    statusBanner("存档未保存：\(error)", symbol: "exclamationmark.triangle", isError: true)
                        .padding(.horizontal, 26).padding(.bottom, 10)
                }
                if let toast = store.toast {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").foregroundStyle(CompanionTheme.accent)
                        Text(toast.text).font(.callout)
                        Spacer()
                        Button(action: store.dismissToast) { Image(systemName: "xmark") }
                            .buttonStyle(.plain).accessibilityLabel("关闭消息")
                    }
                    .padding(11).background(CompanionTheme.sidebar, in: CornerPanelShape(cut: 8))
                    .padding(.horizontal, 26).padding(.bottom, 10)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch section {
                        case .today: todayPage
                        case .focus: focusPage
                        case .care: carePage
                        case .home: PetHomePage(store: store)
                        case .wardrobe: PetWardrobePage(store: store)
                        case .playroom: PetPlayroom(store: store, controller: playroomController, isWorking: isPetWorking)
                        case .shortcuts: shortcutsPage
                        case .files: filesPage
                        case .hardware: hardwarePage
                        case .settings: settingsPage
                        }
                    }
                    .padding(.horizontal, 26).padding(.bottom, 26)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(section == .care ? "care-\(careNavigationRevision)" : (section == .hardware ? "hardware-\(hardwareNavigationRevision)" : section.rawValue))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(CompanionTheme.background)
        .font(.system(.body, design: .rounded))
        .foregroundStyle(CompanionTheme.text)
        .buttonStyle(HUDButtonStyle())
        .tint(CompanionTheme.accent)
        .preferredColorScheme(.light)
        .frame(minWidth: 760, minHeight: 580)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("XiaoKeSelectCare"))) { _ in
            section = .care
            careNavigationRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("XiaoKeSelectHardware"))) { _ in
            section = .hardware
            hardwareNavigationRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("XiaoKeSelectHome"))) { _ in section = .home }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("XiaoKeSelectWardrobe"))) { _ in section = .wardrobe }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("XiaoKeSelectPlayroom"))) { _ in section = .playroom }
        .onChange(of: isPetWorking) { working in
            if working { playroomController.pause(reason: "小可在工作", store: store) }
        }
        .sheet(item: $todoDraft) { draft in
            TodoEditor(draft: draft) { title, details, dueAt in
                if let id = draft.originalID {
                    store.updateTodo(id: id, title: title, details: details, dueAt: dueAt)
                } else {
                    _ = store.addTodo(title: title, details: details, dueAt: dueAt)
                }
                todoDraft = nil
            } onCancel: { todoDraft = nil }
        }
        .sheet(item: $noteDraft) { draft in
            NoteEditor(draft: draft) { title, text in
                if let id = draft.originalID { store.updateNote(id: id, title: title, text: text) }
                else { _ = store.addNote(title: title, text: text) }
                noteDraft = nil
            } onCancel: { noteDraft = nil }
        }
        .sheet(item: $habitDraft) { draft in
            SingleTextEditor(title: "编辑习惯", fieldTitle: "习惯名称", initial: draft.title) { title in
                store.updateHabit(id: draft.id, title: title)
                habitDraft = nil
            } onCancel: { habitDraft = nil }
        }
        .sheet(item: $shortcutDraft) { draft in
            SingleTextEditor(title: "编辑快捷入口", fieldTitle: "显示名称", initial: draft.label) { label in
                store.updateShortcut(id: draft.id, label: label, path: draft.path)
                shortcutDraft = nil
            } onCancel: { shortcutDraft = nil }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    Circle().fill(Color.white.opacity(0.8)).frame(width: 78, height: 78)
                        .overlay(Circle().stroke(CompanionTheme.border.opacity(0.7), lineWidth: 1))
                    petPortrait(height: 88).frame(width: 78, height: 78).offset(y: -3)
                    Image(systemName: "heart.fill").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CompanionTheme.accent).padding(6)
                        .background(CompanionTheme.peach, in: Circle()).offset(x: 3, y: 2)
                }
                Text(store.companionName).font(.system(size: 16, weight: .bold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text("一起过好小小的一天").font(.system(size: 10, design: .rounded))
                    .foregroundStyle(CompanionTheme.secondary)
            }.frame(maxWidth: .infinity).padding(.bottom, 13)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(CompanionSection.allCases) { item in
                        Button { section = item } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.icon).font(.system(size: 15, weight: .medium)).frame(width: 20)
                                Text(item.title).font(.system(size: 12, weight: section == item ? .semibold : .medium, design: .rounded))
                                Spacer(minLength: 0)
                                if section == item { Circle().fill(CompanionTheme.accent).frame(width: 5, height: 5) }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .foregroundStyle(section == item ? CompanionTheme.accent : CompanionTheme.secondary)
                            .background(section == item ? Color.white.opacity(0.94) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: section == item ? CompanionTheme.accent.opacity(0.07) : .clear, radius: 7, y: 3)
                        }.buttonStyle(.plain).accessibilityLabel(item.title)
                    }
                }
            }.scrollIndicators(.hidden)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill").foregroundStyle(CompanionTheme.accent)
                    Text("Lv. \(store.state.stats.level) · \(store.state.stats.experience) XP")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }.foregroundStyle(CompanionTheme.secondary)
                Button(action: actions.showPet) { Label("找到\(store.companionShortName)", systemImage: "pawprint")
                    .font(.system(size: 11, weight: .medium, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75) }
                    .buttonStyle(.plain).foregroundStyle(CompanionTheme.accent)
                    .accessibilityLabel("找到\(store.companionName)")
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 15))
        }
        .padding(.horizontal, 16).padding(.vertical, 20).frame(width: 190).frame(maxHeight: .infinity)
        .background(CompanionTheme.sidebar)
    }

    @ViewBuilder private func petPortrait(height: CGFloat) -> some View {
        if let preview = store.state.settings.appearance.previewImage {
            Image(nsImage: preview).resizable().interpolation(.high).scaledToFit()
                .frame(height: height).accessibilityHidden(true)
        } else {
            Image(systemName: "pawprint.fill").font(.system(size: height * 0.35))
                .foregroundStyle(CompanionTheme.accent).frame(height: height).accessibilityHidden(true)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(section == .today ? "今天的小计划" : section.title)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text(section.subtitle.replacingOccurrences(of: "小可", with: store.companionShortName))
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(CompanionTheme.secondary)
            }
            Spacer()
            if section == .today {
                Button { todoDraft = TodoDraft() } label: { Label("添加待办", systemImage: "plus") }
                    .buttonStyle(HUDButtonStyle(prominent: true)).accessibilityLabel("添加待办")
            } else {
                Image(systemName: section.icon).font(.system(size: 19, weight: .medium))
                    .foregroundStyle(CompanionTheme.accent).frame(width: 43, height: 43)
                    .background(CompanionTheme.lavender.opacity(0.7), in: RoundedRectangle(cornerRadius: 15))
                    .accessibilityHidden(true)
            }
        }.padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 20)
    }

    private var welcomeCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(Date().formatted(.dateTime.month(.wide).day().weekday(.wide)))
                    .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(CompanionTheme.secondary)
                Text("慢慢来，我陪着你。")
                    .font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(CompanionTheme.text)
                Text("把大大的事情，变成一个个小小的完成。")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(CompanionTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Image(systemName: codexMonitor.activeTaskCount > 0 ? "pencil.and.scribble" : "heart.fill")
                    Text(codexMonitor.activeTaskCount > 0 ? "正陪你处理 \(codexMonitor.activeTaskCount) 个任务" : "\(store.companionShortName)在身边")
                }.font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(CompanionTheme.accent).padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Color.white.opacity(0.8), in: Capsule())
            }
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(Color.white.opacity(0.65)).frame(width: 120, height: 120)
                Image(systemName: "sparkle").font(.system(size: 17)).foregroundStyle(CompanionTheme.accent.opacity(0.6))
                    .offset(x: 51, y: -43)
                petPortrait(height: 150).frame(width: 128, height: 144)
            }.accessibilityHidden(true)
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [CompanionTheme.lavender.opacity(0.75), CompanionTheme.peach.opacity(0.75)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.9), lineWidth: 1))
    }

    private var todayPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            welcomeCard
            HStack(spacing: 12) {
                metric("今日完成", value: "\(store.todayProgress.todosCompleted)", icon: "checkmark.circle")
                metric("专注分钟", value: "\(store.todayProgress.focusMinutes)", icon: "timer")
                metric("习惯打卡", value: "\(store.todayProgress.habitCheckIns)", icon: "leaf")
            }
            panelCard {
                HStack {
                    Label("待办清单", systemImage: "checklist").font(.system(size: 15, weight: .bold, design: .rounded))
                    Spacer()
                    Text("\(store.state.todos.filter { !$0.isCompleted }.count) 件待完成")
                        .font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(CompanionTheme.accent)
                        .padding(.horizontal, 9).padding(.vertical, 5).background(CompanionTheme.lavender.opacity(0.6), in: Capsule())
                }
                if store.state.todos.isEmpty {
                    emptyState("今天想完成什么？", detail: "添加第一件待办，\(store.companionShortName)会陪你一点点完成。", icon: "checklist")
                } else {
                    ForEach(store.state.todos.sorted { lhs, rhs in
                        if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
                        return (lhs.dueAt ?? .distantFuture) < (rhs.dueAt ?? .distantFuture)
                    }) { todo in
                        HStack(alignment: .top, spacing: 10) {
                            Button { store.setTodoCompleted(id: todo.id, completed: !todo.isCompleted) } label: {
                                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20)).foregroundStyle(todo.isCompleted ? CompanionTheme.accent : CompanionTheme.secondary)
                            }.buttonStyle(.plain).accessibilityLabel(todo.isCompleted ? "恢复待办：\(todo.title)" : "完成待办：\(todo.title)")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(todo.title).strikethrough(todo.isCompleted).foregroundStyle(todo.isCompleted ? CompanionTheme.secondary : CompanionTheme.text)
                                if !todo.details.isEmpty { Text(todo.details).font(.caption).foregroundStyle(CompanionTheme.secondary).lineLimit(2) }
                                if let date = todo.dueAt {
                                    Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "bell")
                                        .font(.caption2).foregroundStyle(!todo.isCompleted && date < Date() ? CompanionTheme.warning : CompanionTheme.secondary)
                                }
                            }
                            Spacer(minLength: 4)
                            Button { todoDraft = TodoDraft(todo) } label: { Image(systemName: "pencil") }
                                .buttonStyle(.plain).accessibilityLabel("编辑待办：\(todo.title)")
                            Button { store.deleteTodo(id: todo.id) } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain).foregroundStyle(CompanionTheme.secondary).accessibilityLabel("删除待办：\(todo.title)")
                        }.padding(12)
                            .background(todo.isCompleted ? CompanionTheme.mint.opacity(0.42) : CompanionTheme.surfaceRaised.opacity(0.7),
                                        in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                }
            }
            panelCard {
                HStack {
                    Label("随手便签", systemImage: "note.text").font(.system(size: 15, weight: .bold, design: .rounded))
                    Spacer()
                    Button { noteDraft = NoteDraft() } label: { Label("新建便签", systemImage: "plus") }
                        .buttonStyle(HUDButtonStyle()).accessibilityLabel("新建便签")
                }
                if store.state.notes.isEmpty {
                    Text("灵感、备忘、想说的话，都可以先放在这里。")
                        .font(.callout).foregroundStyle(CompanionTheme.secondary).padding(.vertical, 8)
                }
                ForEach(store.state.notes.sorted { lhs, rhs in
                    if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                    return lhs.updatedAt > rhs.updatedAt
                }) { note in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(note.title.isEmpty ? "未命名便签" : note.title).font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Button { store.toggleNotePinned(id: note.id) } label: { Image(systemName: note.isPinned ? "pin.fill" : "pin") }
                                .buttonStyle(.plain).foregroundStyle(note.isPinned ? CompanionTheme.accent : CompanionTheme.secondary)
                                .accessibilityLabel(note.isPinned ? "取消置顶便签" : "置顶便签")
                            Button { noteDraft = NoteDraft(note) } label: { Image(systemName: "pencil") }
                                .buttonStyle(.plain).accessibilityLabel("编辑便签：\(note.title)")
                            Button { store.deleteNote(id: note.id) } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain).foregroundStyle(CompanionTheme.secondary).accessibilityLabel("删除便签：\(note.title)")
                        }
                        Text(note.text).font(.callout).foregroundStyle(CompanionTheme.secondary).lineLimit(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(14).background(CompanionTheme.peach.opacity(0.38), in: CornerPanelShape(cut: 7))
                }
            }
            panelCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: codexMonitor.isListening ? "waveform.path" : "pause.circle")
                        .foregroundStyle(CompanionTheme.accent).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Agent 任务").font(.headline)
                            Spacer()
                            Text("观察到 \(codexMonitor.activeTaskCount) 个进行中")
                                .font(.caption).monospacedDigit().foregroundStyle(CompanionTheme.accent)
                        }
                        Text(codexMonitor.connectionStatus).font(.caption).foregroundStyle(CompanionTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let event = codexMonitor.lastEvent {
                            Text("最近：\(codexEventTitle(event.kind)) · \(event.occurredAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(CompanionTheme.secondary)
                        }
                    }
                    Button("设置") { section = .settings }.accessibilityLabel("打开 Agent 任务提醒设置")
                }
            }
        }
    }

    private var focusPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            panelCard {
                VStack(spacing: 20) {
                    if let cycle = store.state.pomodoro {
                        Text(cycle.phase == .work ? "正在专注" : "休息一下")
                            .font(.headline).foregroundStyle(CompanionTheme.accent)
                        Text(timerText(store.pomodoroRemainingSeconds))
                            .font(.system(size: 64, weight: .light, design: .rounded)).monospacedDigit()
                            .accessibilityLabel("剩余时间 \(timerText(store.pomodoroRemainingSeconds))")
                        Text(cycle.isPaused ? "已经暂停，准备好再继续。" : (cycle.phase == .work ? "慢慢来，把注意力放在眼前这一件事。" : "站起来走走，给眼睛和肩膀放个假。"))
                            .font(.callout).foregroundStyle(CompanionTheme.secondary)
                        HStack(spacing: 12) {
                            Button(cycle.isPaused ? "继续专注" : "暂停计时") {
                                if cycle.isPaused { store.resumePomodoro() } else { store.pausePomodoro() }
                            }.buttonStyle(HUDButtonStyle(prominent: true))
                            Button("结束本轮") { store.cancelPomodoro() }.buttonStyle(HUDButtonStyle())
                        }
                    } else {
                        Image(systemName: "leaf").font(.system(size: 35)).foregroundStyle(CompanionTheme.accent)
                        Text("留一段时间，只做一件事。")
                            .font(.system(size: 20, weight: .medium))
                        HStack(spacing: 22) {
                            Stepper("专注 \(focusMinutes) 分钟", value: $focusMinutes, in: 1...180).frame(width: 180)
                            Stepper("休息 \(breakMinutes) 分钟", value: $breakMinutes, in: 1...60).frame(width: 180)
                        }
                        Button("开始专注") { store.startPomodoro(minutes: focusMinutes, breakMinutes: breakMinutes) }
                            .buttonStyle(HUDButtonStyle(prominent: true)).controlSize(.large)
                    }
                }.frame(maxWidth: .infinity).padding(.vertical, 26)
            }
            panelCard {
                Label("今日已专注 \(store.todayProgress.focusMinutes) 分钟", systemImage: "clock")
                    .font(.headline)
                Text("完成整轮专注会计入记录，也会增加\(store.companionShortName)的经验。暂停期间不会扣除剩余时间。")
                    .font(.callout).foregroundStyle(CompanionTheme.secondary)
            }
        }
    }

    private var isPetWorking: Bool {
        (store.state.pomodoro.map { $0.phase == .work && !$0.isPaused } ?? false)
            || codexMonitor.activeTaskCount > 0 || assistant.isRunning
    }

    private var carePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            PetMoodCard(store: store)
            HStack(spacing: 10) {
                Button { section = .home } label: { Label("布置小窝", systemImage: "house").frame(maxWidth: .infinity) }
                Button { section = .wardrobe } label: { Label("换个搭配", systemImage: "tshirt").frame(maxWidth: .infinity) }
                Button { section = .playroom } label: { Label("玩一分钟", systemImage: "gamecontroller").frame(maxWidth: .infinity) }
            }
            feedingCard
            HStack(spacing: 12) {
                metric("等级", value: "Lv. \(store.state.stats.level)", icon: "sparkles")
                metric("累计经验", value: "\(store.state.stats.experience) XP", icon: "star")
                metric("好感", value: "\(store.state.stats.affection)", icon: "heart")
            }
            panelCard {
                Text("陪\(store.companionShortName)待一会儿").font(.headline)
                HStack(spacing: 12) {
                    interactionButton("摸摸头", icon: "hand.raised", kind: .pet)
                    Button { section = .playroom } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "gamecontroller").font(.system(size: 21))
                            Text("一起玩").font(.callout)
                        }.frame(maxWidth: .infinity).frame(height: 76)
                    }.accessibilityLabel("打开游乐角")
                    interactionButton("歇一会儿", icon: "moon", kind: .rest)
                }
                Text("点点桌面小可的头顶、脸颊和书本，会有不同回应；轻轻拖动还能抱起它。")
                    .font(.caption).foregroundStyle(CompanionTheme.secondary)
                Divider().overlay(CompanionTheme.border.opacity(0.4))
                Text("日常小动作").font(.callout.weight(.semibold))
                HStack(spacing: 7) {
                    dailyAction("揉眼", emoji: "🥱", name: "rub-eyes")
                    dailyAction("伸懒腰", emoji: "🙆", name: "stretch")
                    dailyAction("翻书", emoji: "📖", name: "page-flip")
                    dailyAction("理头发", emoji: "🎀", name: "groom")
                    dailyAction("打哈欠", emoji: "☁️", name: "yawn")
                }
            }
            feedingHistoryCard
            panelCard {
                HStack {
                    Text("解锁相处片段").font(.headline)
                    Spacer()
                    Text("距离下一级还有 \(50 - store.state.stats.experience % 50) XP")
                        .font(.caption).foregroundStyle(CompanionTheme.secondary)
                }
                ProgressView(value: Double(store.state.stats.experience % 50), total: 50)
                    .accessibilityLabel("等级进度 \(store.state.stats.experience % 50) / 50")
                ForEach(PetUnlock.allCases) { action in
                    let unlocked = store.state.stats.level >= action.requiredLevel
                    HStack {
                        Image(systemName: unlocked ? "sparkle" : "lock").foregroundStyle(CompanionTheme.accent)
                        Text(action.title)
                        Spacer()
                        Text("Lv. \(action.requiredLevel)").font(.caption).foregroundStyle(CompanionTheme.secondary)
                        Button(unlocked ? "听\(store.companionShortName)说" : "尚未解锁") { _ = store.performUnlockedAction(action) }
                            .disabled(!unlocked).accessibilityLabel("\(action.title)，\(unlocked ? "听\(store.companionShortName)说" : "需要等级 \(action.requiredLevel)")")
                    }.padding(.vertical, 4)
                }
            }
            panelCard {
                Text("每日小习惯").font(.headline)
                HStack {
                    TextField("例如：喝水、读十页书", text: $habitTitle).textFieldStyle(.plain).modifier(HUDFieldModifier())
                        .accessibilityLabel("新习惯名称").onSubmit(addHabit)
                    Button("添加习惯", action: addHabit).disabled(habitTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if store.state.habits.isEmpty {
                    Text("挑一件简单的小事，坚持就很了不起。")
                        .font(.callout).foregroundStyle(CompanionTheme.secondary).padding(.vertical, 6)
                }
                ForEach(store.state.habits) { habit in
                    HStack {
                        Image(systemName: store.isHabitCheckedInToday(habit) ? "leaf.fill" : "leaf")
                            .foregroundStyle(CompanionTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(habit.title)
                            Text("累计打卡 \(habit.checkIns.count) 天").font(.caption).foregroundStyle(CompanionTheme.secondary)
                        }
                        Spacer()
                        Button(store.isHabitCheckedInToday(habit) ? "今日已打卡" : "打卡") { _ = store.checkInHabit(id: habit.id) }
                            .disabled(store.isHabitCheckedInToday(habit)).accessibilityLabel("打卡：\(habit.title)")
                        Button { habitDraft = HabitDraft(id: habit.id, title: habit.title) } label: { Image(systemName: "pencil") }
                            .buttonStyle(.plain).accessibilityLabel("编辑习惯：\(habit.title)")
                        Button { store.deleteHabit(id: habit.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).foregroundStyle(CompanionTheme.secondary).accessibilityLabel("删除习惯：\(habit.title)")
                    }.padding(.vertical, 6)
                }
            }
            if !store.state.events.isEmpty {
                panelCard {
                    Text("相处记录").font(.headline)
                    ForEach(Array(store.state.events.sorted { $0.createdAt > $1.createdAt }.prefix(6))) { event in
                        HStack(alignment: .top) {
                            Text(event.text).font(.callout)
                            Spacer()
                            Text(event.createdAt.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(CompanionTheme.secondary)
                        }
                    }
                }
            }
        }
    }

    private func dailyAction(_ title: String, emoji: String, name: String) -> some View {
        Button { store.performDailyAction(name) } label: {
            VStack(spacing: 5) {
                Text(emoji).font(.system(size: 20))
                Text(title).font(.system(size: 11, weight: .medium, design: .rounded))
            }.frame(maxWidth: .infinity)
        }.accessibilityLabel("小可\(title)")
    }

    private var shortcutsPage: some View {
        panelCard {
            HStack {
                Text("常用入口").font(.headline)
                Spacer()
                Button(action: actions.addShortcut) { Label("添加入口", systemImage: "plus") }
                    .buttonStyle(HUDButtonStyle(prominent: true)).accessibilityLabel("添加快捷入口")
            }
            if store.state.shortcuts.isEmpty {
                emptyState("把常用的东西放在这里", detail: "选择应用、文件或文件夹，之后点一下就能打开。", icon: "square.grid.2x2")
            }
            ForEach(store.state.shortcuts) { shortcut in
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: shortcut.path)).resizable().frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(shortcut.label).font(.system(size: 13, weight: .semibold))
                        Text(shortcut.path).font(.caption).foregroundStyle(CompanionTheme.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button("打开") { actions.openShortcut(shortcut.id) }.accessibilityLabel("打开快捷入口：\(shortcut.label)")
                    Button { shortcutDraft = ShortcutDraft(id: shortcut.id, label: shortcut.label, path: shortcut.path) } label: { Image(systemName: "pencil") }
                        .buttonStyle(.plain).accessibilityLabel("编辑快捷入口：\(shortcut.label)")
                    Button { store.deleteShortcut(id: shortcut.id) } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundStyle(CompanionTheme.secondary).accessibilityLabel("删除快捷入口：\(shortcut.label)")
                }.padding(.vertical, 8)
            }
        }
    }

    private var filesPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            panelCard {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text").font(.title).foregroundStyle(CompanionTheme.accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(assistant.attachmentURL == nil ? "选择或拖入一个文件" : assistant.attachmentName)
                            .font(.headline).lineLimit(2)
                        Text("放入文件只登记路径。点击本地预览才读取内容。")
                            .font(.caption).foregroundStyle(CompanionTheme.secondary)
                    }
                    Spacer()
                    Button("选择文件", action: actions.chooseFile).disabled(assistant.isRunning)
                }
                HStack {
                    Button("本地预览") { assistant.previewLocal() }
                        .disabled(assistant.attachmentURL == nil || assistant.isRunning)
                    Button("读取剪贴板文字") { assistant.readClipboard() }.disabled(assistant.isRunning)
                    Spacer()
                    if fileDropTargeted { Text("松开即可添加").foregroundStyle(CompanionTheme.accent) }
                }
            }
            .overlay(CornerPanelShape(cut: 10).stroke(fileDropTargeted ? CompanionTheme.accent : Color.clear, lineWidth: 2))
            .onDrop(of: [UTType.fileURL], isTargeted: $fileDropTargeted) { providers in
                guard let provider = providers.first, !assistant.isRunning else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url else { return }
                    Task { @MainActor in assistant.stage(url) }
                }
                return true
            }
            if !assistant.previewText.isEmpty {
                panelCard {
                    Text("本地内容预览").font(.headline)
                    ScrollView {
                        Text(assistant.previewText).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(minHeight: 90, maxHeight: 180)
                }
            }
            panelCard {
                Text("交给 Codex 处理").font(.headline)
                Toggle(isOn: $assistant.allowCodexSending) {
                    Text("允许本次会话把选定内容交给当前 Codex 账号处理")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                }.disabled(assistant.isRunning)
                    .accessibilityLabel("允许本次会话发送选定内容给 Codex")
                Text("勾选后仍需点击下面的处理按钮才会发送。退出后授权不会保留。")
                    .font(.caption).foregroundStyle(CompanionTheme.secondary)
                HStack(spacing: 10) {
                    ForEach(FileAssistantAction.allCases, id: \.rawValue) { action in
                        Button("交给 Codex\(action.title)") { Task { await assistant.run(action) } }
                            .buttonStyle(HUDButtonStyle(prominent: true)).disabled(!assistant.allowCodexSending || assistant.isRunning)
                    }
                    if assistant.isRunning {
                        ProgressView().controlSize(.small)
                        Button("取消处理") { assistant.cancel() }.buttonStyle(HUDButtonStyle())
                    }
                }
                if !assistant.status.isEmpty { Text(assistant.status).font(.caption).foregroundStyle(CompanionTheme.secondary).textSelection(.enabled) }
                if !assistant.errorMessage.isEmpty {
                    statusBanner(assistant.errorMessage, symbol: "exclamationmark.triangle", isError: true)
                }
            }
            if !assistant.resultText.isEmpty {
                panelCard {
                    HStack {
                        Text("处理结果").font(.headline)
                        Spacer()
                        Button("复制结果") { assistant.copyResult() }.accessibilityLabel("复制处理结果")
                    }
                    Text(assistant.resultText).font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            panelCard {
                Text("选择桌宠外观").font(.headline)
                HStack(spacing: 14) {
                    ForEach(PetAppearance.allCases) { appearance in
                        appearanceCard(appearance)
                    }
                }
                Text("两种外观共用同一份待办、便签、专注和养成进度；切换不会重置记录。")
                    .font(.caption).foregroundStyle(CompanionTheme.secondary)
            }
            panelCard {
                Text("外观与相处").font(.headline)
                HStack { Text("\(store.companionShortName)怎么称呼你").frame(width: 130, alignment: .leading)
                    TextField("称呼", text: settingsBinding(\.nickname)).textFieldStyle(.plain).modifier(HUDFieldModifier())
                        .accessibilityLabel("桌宠对你的称呼") }
                HStack { Text("桌宠大小").frame(width: 130, alignment: .leading)
                    Slider(value: settingsBinding(\.scale), in: 0.65...1.5)
                        .accessibilityLabel("桌宠大小")
                    Text("\(Int(store.state.settings.scale * 100))%").font(.caption).monospacedDigit().frame(width: 42) }
                HStack { Text("主动互动频率").frame(width: 130, alignment: .leading)
                    Text("安静").font(.caption).foregroundStyle(CompanionTheme.secondary)
                    Slider(value: settingsBinding(\.interactionFrequency), in: 0...1).accessibilityLabel("主动互动频率")
                    Text("活泼").font(.caption).foregroundStyle(CompanionTheme.secondary) }
                Toggle("视线轻轻跟随鼠标", isOn: settingsBinding(\.mouseFollow))
                Label("右键桌宠，选择「温度与硬件」查看。", systemImage: "thermometer.medium")
                    .font(.caption).foregroundStyle(CompanionTheme.secondary)
                Toggle("鼠标点击穿透桌宠", isOn: settingsBinding(\.clickThrough))
                Text("开启穿透后，可通过菜单栏打开控制面板。")
                    .font(.caption).foregroundStyle(CompanionTheme.secondary)
                Button("显示并找回\(store.companionShortName)", action: actions.showPet)
            }
            panelCard {
                Text("提醒与免打扰").font(.headline)
                Toggle("启用自动提醒", isOn: settingsBinding(\.remindersEnabled))
                Toggle("使用 macOS 系统通知", isOn: settingsBinding(\.nativeNotifications))
                Text("系统通知需要在 macOS 中允许；桌宠的提醒仍受免打扰设置控制。")
                    .font(.caption).foregroundStyle(CompanionTheme.secondary)
                Stepper("久坐提醒：\(store.state.settings.restReminderMinutes == 0 ? "关闭" : "每 \(store.state.settings.restReminderMinutes) 分钟")",
                        value: settingsBinding(\.restReminderMinutes), in: 0...180, step: 15)
                Toggle("开启免打扰时段", isOn: settingsBinding(\.doNotDisturbEnabled))
                if store.state.settings.doNotDisturbEnabled {
                    HStack {
                        Picker("从", selection: settingsBinding(\.quietStartHour)) { ForEach(0..<24, id: \.self) { hour in Text(String(format: "%02d:00", hour)).tag(hour) } }.frame(width: 150)
                        Picker("到", selection: settingsBinding(\.quietEndHour)) { ForEach(0..<24, id: \.self) { hour in Text(String(format: "%02d:00", hour)).tag(hour) } }.frame(width: 150)
                        Spacer()
                    }
                    Text(store.isQuietTime() ? "当前处于免打扰时段。" : "到时间后，\(store.companionShortName)会安静待着。")
                        .font(.caption).foregroundStyle(CompanionTheme.secondary)
                }
            }
            panelCard {
                Text("Agent 任务提醒").font(.headline)
                Toggle("提醒本机 Agent 任务状态", isOn: settingsBinding(\.codexTaskReminders))
                    .accessibilityLabel("Agent 任务提醒")
                Toggle("工作时显示任务进度气泡", isOn: settingsBinding(\.codexProgressBubble))
                    .accessibilityLabel("工作任务进度气泡")
                    .disabled(!store.state.settings.codexTaskReminders)
                Text("多任务每 4 秒轮播，点击气泡可切换下一项。有计划时显示已完成步骤，其他时候显示流动忙碌条；不估算整体完成百分比。完成或互动消息优先显示，之后恢复轮播。")
                    .font(.caption).foregroundStyle(CompanionTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("已接入的 Agent 一轮结束后，桌宠会用气泡和动作提醒。此功能受“启用自动提醒”和免打扰时段控制；系统通知由上方的 macOS 系统通知开关控制。")
                    .font(.caption).foregroundStyle(CompanionTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().overlay(CompanionTheme.border)
                HStack {
                    Text("监听状态").font(.callout)
                    Spacer()
                    Label(codexMonitor.isListening ? "正在监听" : "未监听", systemImage: codexMonitor.isListening ? "waveform.path" : "pause.circle")
                        .font(.caption).foregroundStyle(codexMonitor.isListening ? CompanionTheme.accent : CompanionTheme.secondary)
                }
                Text(codexMonitor.connectionStatus).font(.caption).foregroundStyle(CompanionTheme.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("已观察到进行中").font(.callout)
                    Spacer()
                    Text("\(codexMonitor.activeTaskCount)").font(.callout).monospacedDigit()
                        .accessibilityLabel("监听到 \(codexMonitor.activeTaskCount) 个进行中任务")
                }
                HStack(alignment: .top) {
                    Text("最近事件").font(.callout)
                    Spacer()
                    if let event = codexMonitor.lastEvent {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(codexEventTitle(event.kind)).font(.callout)
                            Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(CompanionTheme.secondary)
                        }
                    } else {
                        Text("尚未收到任务事件").font(.caption).foregroundStyle(CompanionTheme.secondary)
                    }
                }
                Text("Codex 自动读取本机记录；Claude Code 和其他 Agent 使用 xiaoke 命令接入。无需 API Key，不上传聊天内容。通用任务超时后回到空闲，不会误报完成。")
                    .font(.caption).foregroundStyle(CompanionTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            panelCard {
                Text("文件助手 · Codex 连接").font(.headline)
                TextField("Codex 可执行文件路径", text: $assistant.codexExecutablePath)
                    .textFieldStyle(.plain).modifier(HUDFieldModifier()).accessibilityLabel("Codex 可执行文件路径")
                HStack {
                    Button("自动寻找") { assistant.discoverCodex() }
                    Button("检查连接") { Task { await assistant.checkConnection() } }
                    Text(assistant.connectionStatus).font(.caption).foregroundStyle(CompanionTheme.secondary).textSelection(.enabled)
                    Spacer()
                }
                Text("文件处理使用本机 Codex 的登录状态；不会自动发送你的待办、便签或养成记录。")
                    .font(.caption).foregroundStyle(CompanionTheme.secondary)
            }
            panelCard {
                Text("本地存档").font(.headline)
                Text("待办、便签、快捷入口和相处进度会保存在这台电脑。可以导出备份，再在另一台电脑导入。")
                    .font(.callout).foregroundStyle(CompanionTheme.secondary)
                HStack {
                    Button("导出备份", action: actions.exportData)
                    Button("导入备份", action: actions.importData)
                    Spacer()
                    Button("退出桌宠", action: actions.quit)
                }
            }
        }
    }

    private func codexEventTitle(_ kind: AgentTaskEventKind) -> String {
        switch kind {
        case .started: return "任务开始"
        case .completed: return "本轮已完成"
        case .interrupted: return "任务已中断"
        case .failed: return "任务遇到错误"
        }
    }

    private func appearanceCard(_ appearance: PetAppearance) -> some View {
        let selected = store.state.settings.appearance == appearance
        return VStack(spacing: 10) {
            if let preview = appearance.previewImage {
                Image(nsImage: preview).resizable().interpolation(.high).scaledToFit()
                    .frame(height: 130).frame(maxWidth: .infinity)
                    .accessibilityLabel("\(appearance.title)外观预览")
            } else {
                Text("外观预览暂时不可用").font(.caption).foregroundStyle(CompanionTheme.secondary)
                    .frame(height: 130).frame(maxWidth: .infinity)
            }
            HStack(spacing: 6) {
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(CompanionTheme.accent) }
                Text(appearance.title).font(.system(size: 13, weight: .semibold))
            }
            Button(selected ? "正在使用" : "使用这个外观") {
                var settings = store.state.settings
                settings.appearance = appearance
                store.updateSettings(settings)
            }
            .buttonStyle(HUDButtonStyle(prominent: selected))
            .disabled(selected)
            .accessibilityLabel(selected ? "\(appearance.title)，正在使用" : "使用\(appearance.title)外观")
        }
        .padding(14).frame(maxWidth: .infinity)
        .background(CompanionTheme.surfaceRaised.opacity(0.45), in: CornerPanelShape(cut: 8))
        .overlay(CornerPanelShape(cut: 8).stroke(selected ? CompanionTheme.accent.opacity(0.9) : CompanionTheme.border, lineWidth: selected ? 1.5 : 1))
        .shadow(color: selected ? CompanionTheme.accent.opacity(0.1) : .clear, radius: 5)
    }

    private var hardwarePage: some View {
        panelCard {
            HardwareReadingsView(monitor: hardware, compact: false)
            Text("本机实时读数，不存档或同步历史。只显示实际读到的指标。")
                .font(.caption).foregroundStyle(CompanionTheme.secondary)
        }
    }

    private func settingsBinding<Value>(_ path: WritableKeyPath<CompanionSettings, Value>) -> Binding<Value> {
        Binding(get: { store.state.settings[keyPath: path] }, set: { value in
            var settings = store.state.settings
            settings[keyPath: path] = value
            store.updateSettings(settings)
        })
    }

    private func addHabit() {
        let title = habitTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        _ = store.addHabit(title: title)
        habitTitle = ""
    }

    private func timerText(_ remaining: TimeInterval) -> String {
        let seconds = max(0, Int(ceil(remaining)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var feedingCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            panelCard {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("小食堂", systemImage: "fork.knife").font(.headline)
                        Text(store.appetiteDescription)
                            .font(.callout).foregroundStyle(CompanionTheme.secondary)
                    }
                    Spacer()
                    Text("今天想吃点什么？")
                        .font(.caption).foregroundStyle(CompanionTheme.accent)
                }
                HStack(spacing: 20) {
                    feedingMeter("饱腹", value: Double(store.satiety), icon: "fork.knife")
                    feedingMeter("精力", value: store.state.stats.energy, icon: "bolt")
                }
                HStack(spacing: 8) {
                    ForEach(PetFoodCategory.allCases) { category in
                        let count = PetFood.allCases.filter { $0.category == category }.count
                        Button { foodCategory = category } label: {
                            Text("\(category.title) · \(count)")
                                .frame(maxWidth: .infinity).padding(.vertical, 2)
                        }
                        .buttonStyle(HUDButtonStyle(prominent: foodCategory == category))
                        .accessibilityLabel("\(category.title)，\(count)种")
                        .accessibilityValue(foodCategory == category ? "已选择" : "未选择")
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(PetFood.allCases.filter { $0.category == foodCategory }) { food in
                        foodCard(food)
                    }
                }
                Text("食物和牛奶共用 5 分钟消化间隔；温水和茶共用 2 分钟。吃饱后先歇一会儿，也可以喝点水。")
                    .font(.caption).foregroundStyle(CompanionTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func feedingMeter(_ title: String, value: Double, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Text("\(Int(value)) / 100").monospacedDigit()
            }.font(.caption).foregroundStyle(CompanionTheme.secondary)
            ProgressView(value: value, total: 100)
                .accessibilityLabel("\(title) \(Int(value)) / 100")
        }.frame(maxWidth: .infinity)
    }

    private func foodCard(_ food: PetFood) -> some View {
        let remaining = store.feedingCooldownRemaining(food)
        let blocked = store.feedingBlockReason(food)
        let action = food.isLightDrink ? "喝\(food.title)" : "喂\(food.title)"
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Text(food.emoji).font(.system(size: 30)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(food.title).font(.system(size: 15, weight: .semibold))
                    Text(store.foodPreference(food)).font(.caption).foregroundStyle(CompanionTheme.accent)
                    Text(food.detail).font(.caption).foregroundStyle(CompanionTheme.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Text(food.effectDescription)
                .font(.caption).foregroundStyle(CompanionTheme.accent)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
            Button { _ = store.feed(food) } label: {
                HStack(spacing: 6) {
                    Image(systemName: blocked == nil ? (food.isLightDrink ? "drop" : "heart") : "clock")
                    Text(remaining > 0 ? "再等 \(timerText(remaining))" : (blocked == nil ? action : "暂时吃不下"))
                        .monospacedDigit()
                }.frame(maxWidth: .infinity, minHeight: 20)
            }
            .buttonStyle(HUDButtonStyle(prominent: blocked == nil))
            .disabled(blocked != nil)
            .accessibilityLabel(action)
            .accessibilityHint(blocked ?? "\(food.detail)，\(food.effectDescription)")
            .help(blocked ?? food.effectDescription)
            if let blocked, remaining <= 0 {
                Text(blocked).font(.caption2).foregroundStyle(CompanionTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CompanionTheme.sidebar.opacity(0.65), in: CornerPanelShape(cut: 8))
        .overlay(CornerPanelShape(cut: 8).stroke(CompanionTheme.border))
    }

    private var feedingHistoryCard: some View {
        panelCard {
            Label("最近的投喂", systemImage: "clock.arrow.circlepath").font(.headline)
            if store.feedingHistory.isEmpty {
                Text("选一份喜欢的食物，留下第一条投喂记录。")
                    .font(.callout).foregroundStyle(CompanionTheme.secondary)
            } else {
                ForEach(store.feedingHistory) { event in
                    HStack(alignment: .top, spacing: 12) {
                        Text(event.text).font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(CompanionTheme.secondary)
                            .multilineTextAlignment(.trailing)
                    }.padding(.vertical, 2)
                }
            }
        }
    }

    private func interactionButton(_ title: String, icon: String, kind: InteractionKind) -> some View {
        let remaining = store.interactionCooldownRemaining(kind)
        return Button { _ = store.interact(kind) } label: {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 21))
                Text(title).font(.callout)
                if remaining > 0 { Text("\(Int(ceil(remaining))) 秒").font(.caption2).monospacedDigit() }
            }
            .frame(maxWidth: .infinity).frame(height: 76)
        }
        .buttonStyle(HUDButtonStyle()).disabled(remaining > 0).accessibilityLabel(title)
    }

    private func metric(_ title: String, value: String, icon: String) -> some View {
        let tone = icon == "timer" || icon == "star" ? CompanionTheme.peach : (icon == "leaf" || icon == "heart" ? CompanionTheme.mint : CompanionTheme.lavender)
        return HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 17, weight: .medium))
                .foregroundStyle(CompanionTheme.accent).frame(width: 36, height: 36)
                .background(tone.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(value).font(.system(size: 21, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(CompanionTheme.text).lineLimit(1).minimumScaleFactor(0.7)
                Text(title).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(CompanionTheme.secondary)
            }
            Spacer(minLength: 0)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(CompanionTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(CompanionTheme.border.opacity(0.6)))
            .shadow(color: CompanionTheme.accent.opacity(0.035), radius: 8, y: 3)
    }

    private func panelCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(CompanionTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(CompanionTheme.border.opacity(0.6)))
            .shadow(color: CompanionTheme.accent.opacity(0.035), radius: 9, y: 4)
    }

    private func emptyState(_ title: String, detail: String, icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 25, weight: .light)).foregroundStyle(CompanionTheme.accent)
                .frame(width: 60, height: 60).background(CompanionTheme.mint.opacity(0.65), in: RoundedRectangle(cornerRadius: 21))
            Text(title).font(.system(size: 14, weight: .semibold, design: .rounded))
            Text(detail).font(.system(size: 11, design: .rounded)).foregroundStyle(CompanionTheme.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity).padding(.vertical, 18)
    }

    private func statusBanner(_ text: String, symbol: String, isError: Bool) -> some View {
        Label(text, systemImage: symbol).font(.callout).textSelection(.enabled)
            .foregroundStyle(isError ? CompanionTheme.warning : CompanionTheme.accent)
            .padding(11).frame(maxWidth: .infinity, alignment: .leading)
            .background(isError ? CompanionTheme.warning.opacity(0.10) : CompanionTheme.surfaceRaised, in: CornerPanelShape(cut: 7))
    }
}

private struct TodoDraft: Identifiable {
    let id = UUID()
    var originalID: UUID?
    var title = ""
    var details = ""
    var dueAt: Date?
    init() {}
    init(_ todo: TodoItem) { originalID = todo.id; title = todo.title; details = todo.details; dueAt = todo.dueAt }
}

private struct NoteDraft: Identifiable {
    let id = UUID()
    var originalID: UUID?
    var title = ""
    var text = ""
    init() {}
    init(_ note: NoteItem) { originalID = note.id; title = note.title; text = note.text }
}

private struct HabitDraft: Identifiable { var id: UUID; var title: String }
private struct ShortcutDraft: Identifiable { var id: UUID; var label: String; var path: String }

private struct TodoEditor: View {
    let draft: TodoDraft
    let onSave: (String, String, Date?) -> Void
    let onCancel: () -> Void
    @State private var title: String
    @State private var details: String
    @State private var hasReminder: Bool
    @State private var date: Date

    init(draft: TodoDraft, onSave: @escaping (String, String, Date?) -> Void, onCancel: @escaping () -> Void) {
        self.draft = draft; self.onSave = onSave; self.onCancel = onCancel
        _title = State(initialValue: draft.title)
        _details = State(initialValue: draft.details)
        _hasReminder = State(initialValue: draft.dueAt != nil)
        _date = State(initialValue: draft.dueAt ?? Date().addingTimeInterval(3600))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.originalID == nil ? "添加待办" : "编辑待办").font(.title2.weight(.semibold))
            TextField("想完成什么？", text: $title).textFieldStyle(.plain).modifier(HUDFieldModifier()).accessibilityLabel("待办标题")
            Text("补充说明").font(.caption).foregroundStyle(CompanionTheme.secondary)
            TextEditor(text: $details).font(.body).frame(height: 90).scrollContentBackground(.hidden).padding(8).background(CompanionTheme.surfaceRaised).clipShape(CornerPanelShape(cut: 6)).overlay(CornerPanelShape(cut: 6).stroke(CompanionTheme.border)).accessibilityLabel("待办说明")
            Toggle("设置日期与提醒", isOn: $hasReminder).accessibilityLabel("设置待办提醒")
            if hasReminder { DatePicker("提醒时间", selection: $date, displayedComponents: [.date, .hourAndMinute]) }
            HStack {
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("保存待办") { onSave(title.trimmingCharacters(in: .whitespacesAndNewlines), details, hasReminder ? date : nil) }
                    .buttonStyle(HUDButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 440).foregroundStyle(CompanionTheme.text).background(CompanionTheme.background).tint(CompanionTheme.accent).buttonStyle(HUDButtonStyle()).preferredColorScheme(.light)
    }
}

private struct NoteEditor: View {
    let draft: NoteDraft
    let onSave: (String, String) -> Void
    let onCancel: () -> Void
    @State private var title: String
    @State private var text: String
    init(draft: NoteDraft, onSave: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
        self.draft = draft; self.onSave = onSave; self.onCancel = onCancel
        _title = State(initialValue: draft.title); _text = State(initialValue: draft.text)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.originalID == nil ? "新建便签" : "编辑便签").font(.title2.weight(.semibold))
            TextField("便签标题（可选）", text: $title).textFieldStyle(.plain).modifier(HUDFieldModifier()).accessibilityLabel("便签标题")
            TextEditor(text: $text).font(.body).frame(height: 180).scrollContentBackground(.hidden).padding(8).background(CompanionTheme.surfaceRaised).clipShape(CornerPanelShape(cut: 6)).overlay(CornerPanelShape(cut: 6).stroke(CompanionTheme.border)).accessibilityLabel("便签内容")
            HStack {
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("保存便签") { onSave(title.trimmingCharacters(in: .whitespacesAndNewlines), text) }
                    .buttonStyle(HUDButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 440).foregroundStyle(CompanionTheme.text).background(CompanionTheme.background).tint(CompanionTheme.accent).buttonStyle(HUDButtonStyle()).preferredColorScheme(.light)
    }
}

private struct SingleTextEditor: View {
    let title: String
    let fieldTitle: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var value: String
    init(title: String, fieldTitle: String, initial: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.title = title; self.fieldTitle = fieldTitle; self.onSave = onSave; self.onCancel = onCancel
        _value = State(initialValue: initial)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.weight(.semibold))
            TextField(fieldTitle, text: $value).textFieldStyle(.plain).modifier(HUDFieldModifier()).accessibilityLabel(fieldTitle)
            HStack {
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("保存") { onSave(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .buttonStyle(HUDButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 400).foregroundStyle(CompanionTheme.text).background(CompanionTheme.background).tint(CompanionTheme.accent).buttonStyle(HUDButtonStyle()).preferredColorScheme(.light)
    }
}
