import AppKit
import SwiftUI

/// Isolated, offscreen visual QA. Never opens a window or reads the user's save.
@main struct LifeUIPreviews {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/screenshots")
        let dataFolder = FileManager.default.temporaryDirectory.appendingPathComponent("xiaoke-life-ui-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dataFolder) }
        let artworkStart = Date()
        let shared = try PetAppearance.l3d.loadAtlas()
        let coldSeconds = Date().timeIntervalSince(artworkStart)
        let cacheStart = Date()
        for _ in 0..<1000 { let cached = try PetAppearance.l3d.loadAtlas(); precondition(cached === shared) }
        print("Artwork performance: cold=\(coldSeconds)s; 1000 shared lookups=\(Date().timeIntervalSince(cacheStart))s")
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let store = CompanionStore(directory: dataFolder, now: { now })
        var settings = store.state.settings
        settings.appearance = .l3d
        settings.doNotDisturbEnabled = false
        settings.interactionFrequency = 0
        settings.restReminderMinutes = 0
        store.updateSettings(settings)
        store.dismissToast()
        for item in PetHomeItem.allCases { store.setHomeItem(item, enabled: true) }
        store.setAccessory(.sleepCap, enabled: true)
        store.setSeason(.spring)

        func render<V: View>(_ name: String, title: String, view: V) throws {
            let wrapper = VStack(alignment: .leading, spacing: 18) {
                Text(title).font(.system(size: 25, weight: .bold, design: .rounded))
                view
            }
            .padding(24)
            .frame(width: 560, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .font(.system(.body, design: .rounded))
            .foregroundStyle(CompanionTheme.text)
            .buttonStyle(HUDButtonStyle())
            .tint(CompanionTheme.accent)
            .background(CompanionTheme.background)
            .preferredColorScheme(.light)
            let host = NSHostingView(rootView: wrapper)
            host.frame = NSRect(x: 0, y: 0, width: 560, height: 1000)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            let height = ceil(host.fittingSize.height)
            host.frame.size = NSSize(width: 560, height: height)
            window.setContentSize(host.frame.size)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                throw NSError(domain: "LifeUIPreviews", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot allocate offscreen image for \(name)"])
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "LifeUIPreviews", code: 2)
            }
            try png.write(to: folder.appendingPathComponent(name + ".png"))
            print("Rendered \(name): \(Int(host.bounds.width)) × \(Int(host.bounds.height)) points, \(bitmap.pixelsWide) × \(bitmap.pixelsHigh) pixels")
            window.contentView = nil
            window.close()
        }
        try render("home", title: "温暖小窝", view: PetHomePage(store: store))
        try render("wardrobe", title: "小小衣橱", view: PetWardrobePage(store: store))


        let stars = PetPlayroomController()
        stars.start(store: store, at: now)
        stars.advance(store: store, at: now.addingTimeInterval(0.2))
        try render("playroom", title: "游乐角", view: PetPlayroom(store: store, controller: stars, isWorking: false))
        stars.finishEarly(store: store)
        let atlas = try SpriteAtlas(url: folder.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/l3d-spritesheet.png"))
        let canvas = SpriteCanvas(atlas: atlas)
        canvas.frame = NSRect(x: 0, y: 0, width: 320, height: 340)
        canvas.scale = 1.15
        canvas.homeItems = ["cushion", "desk", "lamp", "blanket"]
        canvas.focused = true
        canvas.codexProgressEnabled = true
        canvas.codexTasks = [AgentActiveTask(threadID: "demo", turnID: "demo", title: "[my-agent] 整理项目", startedAt: Date(), updatedAt: Date(), phase: .editing, completedPlanSteps: 2, totalPlanSteps: 3)]
        func capture(_ name: String) throws {
            guard let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { return }
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name + ".png"))
        }
        try capture("working")
        canvas.focused = false
        canvas.codexTasks = []
        canvas.play("sleeping", duration: 30)
        try capture("sleeping")
    }
}
