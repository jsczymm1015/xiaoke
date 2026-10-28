import AppKit
import SwiftUI
import Combine
import UserNotifications
import UniformTypeIdentifiers
import Darwin

@MainActor final class CompanionController: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    private var store: CompanionStore!
    private var assistant: FileAssistant!
    private var hardware: HardwareMonitor!
    private var codexMonitor: AgentTaskMonitor!
    private var petPanel: PetPanel!
    private var canvas: SpriteCanvas!
    private var feedingMenu: FeedingMenuController!
    private var controlWindow: NSWindow?
    private var statusItem: NSStatusItem!
    private var subscriptions: Set<AnyCancellable> = []
    private var clockTimer: Timer?
    private var toastTimer: Timer?
    private var lastSettings: CompanionSettings?
    private var currentFileJob = UUID()
    private var nativeNotificationPermission = false
    private var notificationRequestPending = false
    private var reopenObserver: NSObjectProtocol?
    private var atlases: [PetAppearance: SpriteAtlas] = [:]
    private var diagnostics: RuntimeDiagnostics?
    private var lifecycleObservers: [(NotificationCenter, NSObjectProtocol)] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        reopenObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("XiaoKeShowControlPanel"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.showControlPanel() }
        }
        let base: URL
        if let custom = ProcessInfo.processInfo.environment["XIAOKE_DATA_DIR"], !custom.isEmpty {
            base = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("XiaoKeCompanion", isDirectory: true)
        }
        store = CompanionStore(directory: base)
        feedingMenu = FeedingMenuController(store: store) { [weak self] in
            self?.showControlPanel()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name("XiaoKeSelectCare"), object: nil)
            }
        }
        diagnostics = RuntimeDiagnostics(directory: base)
        diagnostics?.record("launched", details: ["parentPID": String(getppid()),
            "mode": ProcessInfo.processInfo.arguments.contains("--smoke-test") ? "smoke-test" : "normal"])
        assistant = FileAssistant()
        hardware = HardwareMonitor()
        hardware.start()
        codexMonitor = AgentTaskMonitor(cursorDirectory: base.appendingPathComponent("codex-events", isDirectory: true))
        do {
            let appearance = store.state.settings.appearance
            let atlas = try appearance.loadAtlas()
            atlases[appearance] = atlas
            canvas = SpriteCanvas(atlas: atlas)
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法打开小可"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        buildPetPanel()
        buildStatusItem()
        connect()
        observeWindowLifecycle()
        recordRuntimeStatus(force: true)
        UNUserNotificationCenter.current().delegate = self
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.store.tick()
                self.updatePetActivity()
                self.updateStatusTitle()
                self.recordRuntimeStatus()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
        if ProcessInfo.processInfo.arguments.contains("--show-panel") { showControlPanel() }
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") { scheduleSmokeTest() }
    }

    private func buildPetPanel() {
        petPanel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 296),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        petPanel.title = "小可桌宠"
        petPanel.isOpaque = false
        petPanel.backgroundColor = .clear
        petPanel.hasShadow = false
        petPanel.level = .floating
        petPanel.hidesOnDeactivate = false
        petPanel.isFloatingPanel = true
        petPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        petPanel.contentView = canvas
        canvas.autoresizingMask = [.width, .height]
        canvas.setAccessibilityElement(true)
        canvas.setAccessibilityRole(.button)
        canvas.setAccessibilityLabel("小可桌宠：轻点摸头，双击打开陪伴面板，右键更多操作")
        canvas.onTouchZone = { [weak self] zone in self?.store.touchPet(zone: zone) }
        canvas.onDoubleClick = { [weak self] in self?.showControlPanel() }
        canvas.onMoved = { [weak self] origin in
            guard let self = self else { return }
            var s = self.store.state.settings
            s.petX = origin.x
            s.petY = origin.y
            self.store.updateSettings(s)
        }
        canvas.onFile = { [weak self] url in self?.stageFile(url) }
        canvas.menuProvider = { [weak self] in self?.makeMenu() ?? NSMenu() }
        applySettings(store.state.settings)
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "可"
        statusItem.button?.toolTip = "小可桌宠 · 待办、专注与陪伴"
        statusItem.button?.setAccessibilityLabel("小可桌宠菜单")
        statusItem.menu = makeMenu()
    }

    private func connect() {
        store.$state.map(\.life).removeDuplicates().sink { [weak self] life in
            guard let self = self else { return }
            self.canvas.homeItems = Set(life.homeItems.map(\.rawValue))
            self.canvas.outfitItems = Set(life.accessories.map(\.rawValue))
            self.canvas.season = life.season.rawValue
        }.store(in: &subscriptions)
        store.$state.map(\.settings).removeDuplicates().sink { [weak self] settings in self?.applySettings(settings) }.store(in: &subscriptions)
        store.$state.map(\.shortcuts).removeDuplicates().sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.statusItem != nil else { return }
                self.statusItem.menu = self.makeMenu()
            }
        }.store(in: &subscriptions)
        store.$toast.compactMap { $0 }.removeDuplicates(by: { $0.id == $1.id }).sink { [weak self] toast in
            guard let self = self else { return }
            self.canvas.say(toast.text)
            if toast.notifySystem { self.notifyIfEnabled(toast.text) }
            self.toastTimer?.invalidate()
            self.toastTimer = Timer.scheduledTimer(withTimeInterval: 7, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in self?.store.dismissToast() }
            }
        }.store(in: &subscriptions)
        store.$animationRequest.compactMap { $0 }.removeDuplicates(by: { $0.id == $1.id }).sink { [weak self] action in
            self?.canvas.play(action.state, duration: action.duration)
        }.store(in: &subscriptions)
        assistant.$isRunning.removeDuplicates().sink { [weak self] running in
            guard let self = self else { return }
            self.updatePetActivity(assistantRunning: running)
            if running { self.currentFileJob = UUID() }
            else if !self.assistant.resultText.isEmpty && self.assistant.errorMessage.isEmpty {
                self.store.registerFileSuccess(jobID: self.currentFileJob)
                self.canvas.play("review", duration: 3)
            } else { self.canvas.play("idle", duration: 0.2) }
        }.store(in: &subscriptions)
        assistant.$errorMessage.dropFirst().filter { !$0.isEmpty }.sink { [weak self] error in
            self?.canvas.play("failed", duration: 2)
            self?.canvas.say(error)
        }.store(in: &subscriptions)
        codexMonitor.$activeTaskCount.removeDuplicates().sink { [weak self] count in
            self?.updatePetActivity(codexActiveCount: count)
        }.store(in: &subscriptions)
        codexMonitor.$lastEvent.compactMap { $0 }.removeDuplicates(by: { $0.id == $1.id }).sink { [weak self] event in
            guard let self = self, self.store.state.settings.codexTaskReminders else { return }
            self.diagnostics?.record("codex-turn-\(event.kind.rawValue)")
            switch event.kind {
            case .started: break
            case .completed: self.store.notifyCodexTurnEnded(.completed)
            case .failed: self.store.notifyCodexTurnEnded(.failed)
            case .interrupted: break
            }
        }.store(in: &subscriptions)
    }

    private func updatePetActivity(settings: CompanionSettings? = nil, assistantRunning: Bool? = nil, codexActiveCount: Int? = nil) {
        let s = settings ?? store.state.settings
        let focusing = store.state.pomodoro.map { $0.phase == .work && !$0.isPaused } ?? false
        canvas.focused = focusing || (codexActiveCount ?? codexMonitor.activeTaskCount) > 0 || (assistantRunning ?? assistant.isRunning)
        store.setCompanionWorking(canvas.focused)
        canvas.mood = store.petMood.rawValue
        let quiet = store.isQuietTime(settings: s)
        canvas.quiet = quiet
        canvas.codexTasks = codexMonitor.activeTasks
        canvas.codexProgressEnabled = s.codexTaskReminders && s.codexProgressBubble && codexMonitor.isListening
        canvas.codexProgressVisible = s.remindersEnabled && !quiet && s.petVisible
    }

    private func applySettings(_ s: CompanionSettings) {
        guard petPanel != nil else { return }
        let previous = lastSettings
        lastSettings = s
        if previous?.appearance != s.appearance {
            do {
                let atlas = try atlases[s.appearance] ?? s.appearance.loadAtlas()
                atlases[s.appearance] = atlas
                canvas.replaceAtlas(atlas)
                petPanel.title = s.appearance.title
                canvas.setAccessibilityLabel("\(s.appearance.title)：轻点互动，双击打开面板，右键更多操作")
            } catch { canvas.say("这个外观的资源无法打开：\(error.localizedDescription)") }
        }
        canvas.scale = s.scale
        canvas.mouseFollow = s.mouseFollow
        petPanel.ignoresMouseEvents = s.clickThrough
        let size = NSSize(width: max(264, 192 * s.scale + 36), height: 208 * s.scale + 88)
        var origin = petPanel.frame.origin
        if previous == nil {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            origin = NSPoint(x: s.petX ?? screen.maxX - size.width - 28, y: s.petY ?? screen.minY + 24)
        } else if previous?.petX != s.petX || previous?.petY != s.petY {
            origin = NSPoint(x: s.petX ?? origin.x, y: s.petY ?? origin.y)
        }
        let fitted = PetWindowPlacement.fit(NSRect(origin: origin, size: size), in: NSScreen.screens.map(\.visibleFrame), preferred: NSScreen.main?.visibleFrame)
        canvas.scale = max(0.2, min(s.scale, (fitted.width - 36) / 192, (fitted.height - 88) / 208))
        if petPanel.frame != fitted {
            petPanel.setFrame(fitted, display: true)
        }
        if s.petVisible { petPanel.orderFrontRegardless() } else { petPanel.orderOut(nil) }
        if s.nativeNotifications && previous?.nativeNotifications != true { requestNotifications() }
        if s.codexTaskReminders && previous?.codexTaskReminders != true { codexMonitor.start() }
        if !s.codexTaskReminders && previous?.codexTaskReminders != false { codexMonitor.stop() }
        updatePetActivity(settings: s)
        if statusItem != nil {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.statusItem.menu = self.makeMenu()
            }
        }
    }

    func showControlPanel() {
        if controlWindow == nil {
            let actions = PanelActions(
                showPet: { [weak self] in self?.showPet() },
                chooseFile: { [weak self] in self?.chooseFile() },
                addShortcut: { [weak self] in self?.addShortcut() },
                openShortcut: { [weak self] id in self?.openShortcut(id) },
                exportData: { [weak self] in self?.exportData() },
                importData: { [weak self] in self?.importData() },
                quit: { NSApp.terminate(nil) })
            let root = CompanionPanel(store: store, assistant: assistant, hardware: hardware, codexMonitor: codexMonitor, actions: actions)
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 690),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "小可 · 工作与陪伴"
            w.appearance = NSAppearance(named: .aqua)
            w.minSize = NSSize(width: 780, height: 620)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: root)
            w.center()
            controlWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        controlWindow?.makeKeyAndOrderFront(nil)
    }

    func showPet() {
        var s = store.state.settings
        s.petVisible = true
        store.updateSettings(s)
        recoverPetWindow(reason: "show-request")
        canvas.say("我在这里。双击我，就能打开陪伴面板。")
    }

    private func stageFile(_ url: URL) {
        assistant.stage(url)
        assistant.previewLocal()
        showControlPanel()
        NotificationCenter.default.post(name: Notification.Name("XiaoKeSelectFiles"), object: nil)
        canvas.play("review", duration: 2)
        canvas.say("文件已放好，先看看，再决定怎么处理。")
    }
    private func chooseFile() {
        let picker = NSOpenPanel()
        picker.title = "选择要交给小可的文件"
        picker.prompt = "本地预览"
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        if picker.runModal() == .OK, let url = picker.url { stageFile(url) }
    }
    private func addShortcut() {
        let picker = NSOpenPanel()
        picker.title = "选择常用应用、文件或文件夹"
        picker.prompt = "添加快捷入口"
        picker.canChooseDirectories = true
        picker.canChooseFiles = true
        picker.allowsMultipleSelection = false
        if picker.runModal() == .OK, let url = picker.url {
            _ = store.addShortcut(label: url.deletingPathExtension().lastPathComponent, path: url.path)
        }
    }
    private func openShortcut(_ id: UUID) {
        guard let item = store.state.shortcuts.first(where: { $0.id == id }) else { return }
        let url = URL(fileURLWithPath: item.path)
        guard FileManager.default.fileExists(atPath: url.path) else { canvas.say("这个入口的文件找不到了，可以重新添加。 "); return }
        if !NSWorkspace.shared.open(url) { canvas.say("暂时无法打开这个入口，请检查默认打开应用。") }
    }
    private func exportData() {
        let picker = NSSavePanel()
        picker.title = "导出小可的本地存档"
        picker.nameFieldStringValue = "小可存档.json"
        picker.allowedContentTypes = [.json]
        if picker.runModal() == .OK, let url = picker.url {
            do { try store.exportState(to: url); canvas.say("存档已保存好。") }
            catch { showError("无法导出存档", error.localizedDescription) }
        }
    }
    private func importData() {
        let picker = NSOpenPanel()
        picker.title = "导入小可存档（当前存档会先备份）"
        picker.allowedContentTypes = [.json]
        picker.canChooseDirectories = false
        if picker.runModal() == .OK, let url = picker.url {
            do { try store.importState(from: url); canvas.say("欢迎回来，存档已经接上了。") }
            catch { showError("无法导入存档", error.localizedDescription) }
        }
    }
    private func showError(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "小可")
        func item(_ title: String, _ action: Selector, key: String = "") {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.target = self
            menu.addItem(i)
        }
        item("打开工作与陪伴面板", #selector(openPanel), key: "k")
        menu.addItem(.separator())
        item("轻轻摸头", #selector(touch))
        menu.addItem(feedingMenu.makeMenuItem())
        item("陪我放松一下", #selector(play))
        item("布置小窝", #selector(openHome))
        item("打开衣橱", #selector(openWardrobe))
        item("一分钟游乐角", #selector(openPlayroom))
        item("开始 25 分钟专注", #selector(focus))
        item("选择文件…", #selector(pickFile))
        item("温度与硬件", #selector(openHardware))
        if store != nil && !store.state.shortcuts.isEmpty {
            let sub = NSMenu(title: "快捷入口")
            for shortcut in store.state.shortcuts {
                let i = NSMenuItem(title: shortcut.label, action: #selector(shortcutClicked(_:)), keyEquivalent: "")
                i.target = self
                i.representedObject = shortcut.id
                sub.addItem(i)
            }
            let i = NSMenuItem(title: "快捷入口", action: nil, keyEquivalent: "")
            i.submenu = sub
            menu.addItem(i)
        }
        menu.addItem(.separator())
        if store != nil {
            item(store.state.settings.petVisible ? "暂时隐藏小可" : "显示小可", #selector(togglePet))
            item(store.state.settings.clickThrough ? "恢复鼠标互动" : "鼠标穿透（从菜单恢复）", #selector(toggleClickThrough))
        }
        item("退出小可桌宠", #selector(quit), key: "q")
        return menu
    }
    @objc private func openPanel() { showControlPanel() }
    @objc private func openHardware() {
        showControlPanel()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("XiaoKeSelectHardware"), object: nil)
        }
    }
    @objc private func openHome() { openLifePage("XiaoKeSelectHome") }
    @objc private func openWardrobe() { openLifePage("XiaoKeSelectWardrobe") }
    @objc private func openPlayroom() { openLifePage("XiaoKeSelectPlayroom") }
    private func openLifePage(_ notification: String) {
        showControlPanel()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name(notification), object: nil)
        }
    }
    @objc private func touch() { store.touchPet(zone: "head") }
    @objc private func play() { store.interact(.play) }
    @objc private func focus() { store.startPomodoro(minutes: 25) }
    @objc private func pickFile() { chooseFile() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func shortcutClicked(_ sender: NSMenuItem) { if let id = sender.representedObject as? UUID { openShortcut(id) } }
    @objc private func togglePet() {
        var s = store.state.settings
        s.petVisible.toggle()
        store.updateSettings(s)
        diagnostics?.record(s.petVisible ? "pet-shown" : "pet-hidden")
        if s.petVisible { recoverPetWindow(reason: "menu-show") }
        recordRuntimeStatus(force: true)
    }
    @objc private func toggleClickThrough() { var s = store.state.settings; s.clickThrough.toggle(); store.updateSettings(s) }

    private func updateStatusTitle() {
        guard let statusItem = statusItem else { return }
        if let p = store.state.pomodoro {
            let seconds = max(0, Int(ceil(store.pomodoroRemainingSeconds)))
            statusItem.button?.title = "可 \(p.isPaused ? "Ⅱ " : "")\(seconds / 60):\(String(format: "%02d", seconds % 60))"
        } else { statusItem.button?.title = "可" }
    }
    private func requestNotifications() {
        guard !notificationRequestPending else { return }
        notificationRequestPending = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] allowed, _ in
            DispatchQueue.main.async {
                self?.nativeNotificationPermission = allowed
                self?.notificationRequestPending = false
                if !allowed { self?.canvas.say("系统通知暂未开启，提醒仍会显示在我的气泡里。") }
            }
        }
    }
    private func notifyIfEnabled(_ text: String) {
        guard store.state.settings.nativeNotifications, nativeNotificationPermission,
              !store.isQuietTime() else { return }
        let content = UNMutableNotificationContent()
        content.title = store.companionName
        content.body = text
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in self?.showControlPanel() }
        completionHandler()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showControlPanel(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        diagnostics?.record("termination-requested", details: ["fileJobRunning": String(assistant?.isRunning == true)])
        guard assistant?.isRunning == true else { return .terminateNow }
        assistant.cancel()
        Task { @MainActor [weak self] in
            let deadline = Date().addingTimeInterval(4)
            while self?.assistant.isRunning == true && Date() < deadline {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        diagnostics?.record("clean-exit")
        recordRuntimeStatus(force: true, closed: true)
        assistant?.cancel(); store?.save(); hardware?.stop(); codexMonitor?.stop()
        clockTimer?.invalidate(); toastTimer?.invalidate()
        for (center, observer) in lifecycleObservers { center.removeObserver(observer) }
        if let observer = reopenObserver { DistributedNotificationCenter.default().removeObserver(observer) }
    }
    func windowWillClose(_ notification: Notification) { store.save(); diagnostics?.record("control-panel-closed") }

    private func observeWindowLifecycle() {
        let center = NotificationCenter.default
        let screens = center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.recoverPetWindow(reason: "screens-changed") }
        }
        lifecycleObservers.append((center, screens))
        let workspace = NSWorkspace.shared.notificationCenter
        let wake = workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.recoverPetWindow(reason: "wake") }
        }
        lifecycleObservers.append((workspace, wake))
        let sleep = workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.diagnostics?.record("sleep")
                self?.recordRuntimeStatus(force: true)
            }
        }
        lifecycleObservers.append((workspace, sleep))
    }

    private func recoverPetWindow(reason: String) {
        guard let petPanel, let store, !NSScreen.screens.isEmpty else { return }
        let before = petPanel.frame
        let fitted = PetWindowPlacement.fit(before, in: NSScreen.screens.map(\.visibleFrame), preferred: NSScreen.main?.visibleFrame)
        if before != fitted {
            petPanel.setFrame(fitted, display: true)
            canvas.scale = max(0.2, min(store.state.settings.scale, (fitted.width - 36) / 192, (fitted.height - 88) / 208))
            var settings = store.state.settings
            settings.petX = fitted.minX
            settings.petY = fitted.minY
            store.updateSettings(settings)
        }
        if store.state.settings.petVisible { petPanel.orderFrontRegardless() }
        diagnostics?.record("window-recovered", details: ["reason": reason, "moved": String(before != fitted), "enabled": String(store.state.settings.petVisible)])
        recordRuntimeStatus(force: true)
    }

    private func recordRuntimeStatus(force: Bool = false, closed: Bool = false) {
        guard let petPanel, let store else { return }
        diagnostics?.heartbeat(petVisible: store.state.settings.petVisible, windowVisible: petPanel.isVisible,
            frame: petPanel.frame, screens: NSScreen.screens.count, force: force, closed: closed)
    }

    /// Exercises native window creation without touching the user's normal save.
    private func scheduleSmokeTest() {
        showControlPanel()
        let output = ProcessInfo.processInfo.environment["XIAOKE_QA_DIR"].map { URL(fileURLWithPath: $0) } ?? store.directory
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self else { return }
            do {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                if let cv = self.controlWindow?.contentView,
                   let bitmap = cv.bitmapImageRepForCachingDisplay(in: cv.bounds) {
                    cv.cacheDisplay(in: cv.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("control-panel.png"))
                }
                self.canvas.play("idle", duration: 1)
                let bitmap = self.canvas.bitmapImageRepForCachingDisplay(in: self.canvas.bounds)!
                self.canvas.cacheDisplay(in: self.canvas.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("desktop-pet.png"))
                let report: [String: Any] = ["nativeWindowCreated": true, "transparentWindow": !self.petPanel.isOpaque,
                    "spriteRows": self.canvas.atlas.frames.count, "lookFrames": self.canvas.atlas.looks.count,
                    "controlWindowVisible": self.controlWindow?.isVisible == true,
                    "saveCreated": FileManager.default.fileExists(atPath: self.store.saveURL.path),
                    "codexDetected": !self.assistant.codexExecutablePath.isEmpty]
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("native-smoke.json"))
            } catch { fputs("Smoke test failed: \(error)\n", stderr) }
            NSApp.terminate(nil)
        }
    }
}

@main struct XiaoKeLauncher {
    @MainActor static func main() {
        let lockPath = "/private/tmp/xiaoke-companion-\(getuid()).lock"
        let lockFD = open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            if lockFD >= 0 { close(lockFD) }
            DistributedNotificationCenter.default().postNotificationName(Notification.Name("XiaoKeShowControlPanel"), object: nil, userInfo: nil, deliverImmediately: true)
            return
        }
        defer { flock(lockFD, LOCK_UN); close(lockFD) }
        let app = NSApplication.shared
        let controller = CompanionController()
        app.delegate = controller
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(controller) { app.run() }
    }
}
