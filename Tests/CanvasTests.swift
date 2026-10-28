import AppKit
import Foundation

/// Native rendering and event tests using synthetic tasks, never the user's task logs.
@main
struct CanvasTests {
    @MainActor static func main() throws {
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            assertions += 1
            guard condition() else { throw NSError(domain: "CanvasTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func argument(_ flag: String) -> String? {
            guard let index = CommandLine.arguments.firstIndex(of: flag), CommandLine.arguments.indices.contains(index + 1) else { return nil }
            return CommandLine.arguments[index + 1]
        }
        let resources = URL(fileURLWithPath: argument("--resources") ?? FileManager.default.currentDirectoryPath + "/Resources")
        let output = URL(fileURLWithPath: argument("--output-dir") ?? NSTemporaryDirectory() + "xiaoke-canvas-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let atlas = try SpriteAtlas(url: resources.appendingPathComponent("spritesheet.png"))
        try expect(!atlas.hasActivities && atlas.frames.count == 9, "A skin without an activity sidecar must keep its original nine rows")

        // Deliberately synthetic colors test loading and state transitions without inventing pet artwork.
        let fixture = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("xiaoke-activities-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let fixtureAtlasURL = fixture.appendingPathComponent("test-spritesheet.png")
        try FileManager.default.copyItem(at: resources.appendingPathComponent("spritesheet.png"), to: fixtureAtlasURL)
        let activityURL = fixture.appendingPathComponent("test-spritesheet-activities.png")
        let activityBitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1152, pixelsHigh: 416,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 1152 * 4, bitsPerPixel: 32)!
        let pixels = activityBitmap.bitmapData!
        for y in 0..<416 {
            for x in 0..<1152 {
                let offset = y * activityBitmap.bytesPerRow + x * 4
                pixels[offset] = y < 208 ? 220 : 20
                pixels[offset + 1] = UInt8(30 + (x / 192) * 30)
                pixels[offset + 2] = y < 208 ? 20 : 220
                pixels[offset + 3] = 255
            }
        }
        try activityBitmap.representation(using: .png, properties: [:])!.write(to: activityURL)
        let activityAtlas = try SpriteAtlas(url: fixtureAtlasURL)
        try expect(activityAtlas.writingFrames?.count == 6 && activityAtlas.sleepingFrames?.count == 6, "The optional sidecar must decode exactly six writing and six sleeping frames")
        let writingPixel = NSBitmapImageRep(data: activityAtlas.writingFrames![0].tiffRepresentation!)!.colorAt(x: 96, y: 104)!.usingColorSpace(.deviceRGB)!
        let sleepingPixel = NSBitmapImageRep(data: activityAtlas.sleepingFrames![0].tiffRepresentation!)!.colorAt(x: 96, y: 104)!.usingColorSpace(.deviceRGB)!
        try expect(writingPixel.redComponent > 0.8 && sleepingPixel.blueComponent > 0.8, "The upper sidecar row is writing and the lower row is sleeping")
        let lifeURL = fixture.appendingPathComponent("test-spritesheet-life.png")
        let lifeBitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1152, pixelsHigh: 2080,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 1152 * 4, bitsPerPixel: 32)!
        for y in 0..<2080 {
            for x in 0..<1152 {
                let offset = y * lifeBitmap.bytesPerRow + x * 4
                lifeBitmap.bitmapData![offset] = UInt8(20 + (y / 208) * 20)
                lifeBitmap.bitmapData![offset + 1] = UInt8(20 + (x / 192) * 30)
                lifeBitmap.bitmapData![offset + 2] = 140
                lifeBitmap.bitmapData![offset + 3] = 255
            }
        }
        try lifeBitmap.representation(using: .png, properties: [:])!.write(to: lifeURL)
        let foodURL = fixture.appendingPathComponent("test-spritesheet-foods.png")
        let foodFixtureImage = lifeBitmap.cgImage!.cropping(to: CGRect(x: 0, y: 0, width: 1152, height: 832))!
        try NSBitmapImageRep(cgImage: foodFixtureImage).representation(using: .png, properties: [:])!.write(to: foodURL)
        let lifeAtlas = try SpriteAtlas(url: fixtureAtlasURL)
        try expect(lifeAtlas.lifeFrames.count == 10 && lifeAtlas.lifeFrames.values.allSatisfy { $0.count == 6 }, "The life atlas must contain ten six-frame action rows")
        var activityNow = Date(timeIntervalSince1970: 1_700_000_000)
        let activityCanvas = SpriteCanvas(atlas: activityAtlas, now: { activityNow })
        let activityWindow = PetPanel(contentRect: activityCanvas.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        activityWindow.contentView = activityCanvas
        defer { activityWindow.close() }
        activityNow += 7.9
        activityCanvas.advance()
        try expect(!activityCanvas.isSleeping && activityCanvas.state == .idle, "Idle begins standing, with time for pointer interaction")
        activityNow += 0.2
        activityCanvas.advance()
        try expect(activityCanvas.isSleeping && activityCanvas.lookIndex == nil && activityCanvas.animationFPS == 1.5, "Eight idle seconds must start slow sleeping, without mouse-look overriding it")
        try expect(activityCanvas.currentImage === activityAtlas.sleepingFrames![0], "Sleeping must render the sidecar rather than the original idle artwork")
        activityCanvas.focused = true
        try expect(!activityCanvas.isSleeping && activityCanvas.state == .running && activityCanvas.animationFPS == 3, "New work must immediately wake the pet into the writing cycle")
        try expect(activityCanvas.currentImage === activityAtlas.writingFrames![0], "Work must select the writing sidecar")
        activityNow += 0.34
        activityCanvas.advance()
        try expect(activityCanvas.frameIndex == 1, "Writing advances at three frames per second")
        activityCanvas.play("review", duration: 2)
        activityCanvas.focused = false
        try expect(activityCanvas.state == .review && !activityCanvas.isSleeping, "A completion interaction may finish when work ends")
        activityNow += 2.1
        activityCanvas.advance()
        try expect(activityCanvas.state == .idle && !activityCanvas.isSleeping, "Completion must return to standing and reset the idle delay")
        activityNow += 7.9
        activityCanvas.advance()
        try expect(!activityCanvas.isSleeping, "The sleep delay restarts after the interaction finishes")
        activityNow += 0.2
        activityCanvas.advance()
        try expect(activityCanvas.isSleeping, "The pet resumes sleeping after the new idle delay")
        let wakeDown = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 125, y: 104), modifierFlags: [], timestamp: 0,
            windowNumber: activityWindow.windowNumber, context: nil, eventNumber: 90, clickCount: 1, pressure: 1)!
        let wakeUp = NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: 125, y: 104), modifierFlags: [], timestamp: 0,
            windowNumber: activityWindow.windowNumber, context: nil, eventNumber: 91, clickCount: 1, pressure: 0)!
        activityCanvas.mouseDown(with: wakeDown)
        try expect(!activityCanvas.isSleeping, "Touch and the start of a drag must wake the sleeping pet")
        activityCanvas.mouseUp(with: wakeUp)
        activityCanvas.play("sleeping", duration: 2)
        try expect(activityCanvas.isSleeping, "An explicit rest interaction can begin sleeping immediately")
        activityCanvas.focused = true
        activityCanvas.play("running", duration: 180)
        activityCanvas.focused = false
        try expect(activityCanvas.state == .idle && !activityCanvas.isSleeping, "Ending live work must clear a stale long running animation")
        activityCanvas.play("sleeping")
        activityCanvas.replaceAtlas(atlas)
        try expect(!activityCanvas.isSleeping && !activityCanvas.atlas.hasActivities, "Changing to a legacy skin must clear the optional sleeping pose")
        activityNow += 100
        activityCanvas.advance()
        activityNow += 100
        activityCanvas.advance()
        try expect(!activityCanvas.isSleeping && activityCanvas.animationFPS == SpriteState.idle.fps, "A skin without a sidecar must keep its original idle behavior after long inactivity")
        let wrongSize = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 192, pixelsHigh: 208,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 192 * 4, bitsPerPixel: 32)!
        wrongSize.bitmapData!.initialize(repeating: 0, count: wrongSize.bytesPerRow * wrongSize.pixelsHigh)
        try wrongSize.representation(using: .png, properties: [:])!.write(to: activityURL)
        do {
            _ = try SpriteAtlas(url: fixtureAtlasURL)
            try expect(false, "A malformed present sidecar must not be silently cropped")
        } catch let error as NSError {
            try expect(error.domain == "XiaoKe" && error.code == 2, "A malformed sidecar must report the asset error")
        }
        var lifeNow = Date(timeIntervalSince1970: 1_700_000_000)
        let lifeCanvas = SpriteCanvas(atlas: lifeAtlas, now: { lifeNow })
        let lifeWindow = PetPanel(contentRect: lifeCanvas.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        lifeWindow.contentView = lifeCanvas
        defer { lifeWindow.close() }
        for name in SpriteAtlas.lifeRows {
            lifeCanvas.play(name, duration: 4)
            try expect(lifeCanvas.currentImage === (name == "touch" ? lifeAtlas.frames[SpriteState.idle.row][0] : lifeAtlas.lifeFrames[name]![0]), "Life action selects its intended artwork (touch preserves normal pose): \(name)")
        }
        try expect(lifeAtlas.foodFrames.count == 4 && lifeAtlas.foodFrames.values.allSatisfy { $0.count == 6 }, "The optional food atlas must decode four six-frame rows")
        for food in SpriteAtlas.foodRows {
            lifeCanvas.play("eat-" + food, duration: 4)
            try expect(lifeCanvas.currentImage === lifeAtlas.foodFrames[food]![0], "Each food request must select its matching artwork: \(food)")
        }
        lifeCanvas.play("eat-cookie", duration: 4)
        try expect(lifeCanvas.lifeAnimation == "eat" && lifeCanvas.animationFPS == 1.75, "Feeding must use the slower actual eating row")
        try expect(lifeCanvas.currentImage === lifeAtlas.lifeFrames["eat"]![0], "Cookies must retain the life atlas cookie animation")
        lifeCanvas.play("drink-milk", duration: 4)
        try expect(lifeCanvas.currentImage === lifeAtlas.lifeFrames["drink"]![0], "Milk must use the actual drinking row")
        lifeNow += 0.6; lifeCanvas.advance()
        try expect(lifeCanvas.frameIndex == 1, "Eating and drinking frames must visibly advance")
        lifeCanvas.beginCarrying()
        try expect(lifeCanvas.isCarried && lifeCanvas.lifeAnimation == "carry" && !lifeCanvas.isSleeping, "Picking up must suspend normal activity into the dangling-leg cycle")
        lifeCanvas.play("celebrating", duration: 1)
        try expect(lifeCanvas.lifeAnimation == "carry", "An incoming reward animation cannot interrupt carrying")
        lifeNow += 1; lifeCanvas.advance()
        try expect(lifeCanvas.currentImage === lifeAtlas.lifeFrames["carry"]![lifeCanvas.frameIndex], "Carried animation must remain the selected atlas")
        lifeCanvas.finishCarrying()
        try expect(!lifeCanvas.isCarried && lifeCanvas.lifeAnimation == "land", "Putting down must begin landing and tidying")
        lifeNow += 2.3; lifeCanvas.advance()
        try expect(lifeCanvas.lifeAnimation == nil && lifeCanvas.state == .idle, "Landing finishes into the live activity")
        let pr = lifeCanvas.petRect
        try expect(lifeCanvas.touchZone(at: NSPoint(x: pr.midX, y: pr.minY + 25)) == "head", "The upper hair is the head touch zone")
        try expect(lifeCanvas.touchZone(at: NSPoint(x: pr.midX, y: pr.minY + 70)) == "face", "The face is a separate touch zone")
        try expect(lifeCanvas.touchZone(at: NSPoint(x: pr.midX, y: pr.minY + 118)) == "book", "The book has its own touch zone")
        try expect(lifeCanvas.touchZone(at: NSPoint(x: pr.minX + 5, y: pr.minY + 70)) == nil, "Transparent side margins must not reward touch")
        lifeCanvas.play("touch-book")
        try expect(lifeCanvas.lifeAnimation == "touch", "Touching the book preserves normal artwork; ambient page flips remain separate")
        lifeCanvas.play("sleeping", duration: 1)
        try expect(lifeCanvas.touchZone(at: NSPoint(x: pr.midX, y: pr.minY + 110)) == "face", "Sleeping touch regions must follow the bowed head")
        lifeNow += 1.1; lifeCanvas.advance()
        lifeCanvas.focused = true
        lifeNow += 32.1; lifeCanvas.advance()
        try expect(lifeCanvas.lifeAnimation == "page-flip", "Working must occasionally flip the book's pages")
        lifeNow += 2.2; lifeCanvas.advance()
        try expect(lifeCanvas.lifeAnimation == nil && lifeCanvas.state == .running, "Ambient page flipping must return to writing")
        lifeCanvas.quiet = true
        lifeNow += 40; lifeCanvas.advance()
        try expect(lifeCanvas.lifeAnimation == nil, "Quiet mode must suppress spontaneous life animations")
        lifeCanvas.play("drink-water")
        try expect(lifeCanvas.lifeAnimation == "drink", "Quiet mode must still honor explicitly requested feeding")
        lifeCanvas.focused = false
        lifeCanvas.quiet = false
        lifeCanvas.play("idle", duration: 0.2)
        lifeNow += 0.3; lifeCanvas.advance()
        lifeNow += 8.1; lifeCanvas.advance()
        try expect(lifeCanvas.isSleeping, "New life features must retain eight-second low-head dozing")
        var selectedZones: [String] = []
        var legacyTouches = 0
        lifeCanvas.onTouchZone = { selectedZones.append($0) }
        lifeCanvas.onTouch = { legacyTouches += 1 }
        let sleepingFace = NSPoint(x: pr.midX, y: lifeCanvas.bounds.height - (pr.minY + 110))
        for index in 0..<4 {
            let d = NSEvent.mouseEvent(with: .leftMouseDown, location: sleepingFace, modifierFlags: [], timestamp: 0,
                windowNumber: lifeWindow.windowNumber, context: nil, eventNumber: 100 + index * 2, clickCount: 1, pressure: 1)!
            let u = NSEvent.mouseEvent(with: .leftMouseUp, location: sleepingFace, modifierFlags: [], timestamp: 0,
                windowNumber: lifeWindow.windowNumber, context: nil, eventNumber: 101 + index * 2, clickCount: 1, pressure: 0)!
            lifeCanvas.mouseDown(with: d); lifeCanvas.mouseUp(with: u)
        }
        try expect(selectedZones.first == "face" && legacyTouches == 0, "A sleeping touch is identified before waking, and never calls both reward callbacks")
        try expect(lifeCanvas.animationName == "dodge", "Repeated quick touches must produce a gentle dodge")
        try wrongSize.representation(using: .png, properties: [:])!.write(to: lifeURL)
        try activityBitmap.representation(using: .png, properties: [:])!.write(to: activityURL)
        do {
            _ = try SpriteAtlas(url: fixtureAtlasURL)
            try expect(false, "A malformed present life atlas must be rejected")
        } catch let error as NSError {
            try expect(error.domain == "XiaoKe" && error.code == 3, "A malformed life atlas must report its specific asset error")
        }
        try lifeBitmap.representation(using: .png, properties: [:])!.write(to: lifeURL)
        try wrongSize.representation(using: .png, properties: [:])!.write(to: foodURL)
        do {
            _ = try SpriteAtlas(url: fixtureAtlasURL)
            try expect(false, "A malformed present food atlas must be rejected")
        } catch let error as NSError {
            try expect(error.domain == "XiaoKe" && error.code == 4, "A malformed food atlas must report its specific asset error")
        }
        let canvas = SpriteCanvas(atlas: atlas)
        canvas.frame = NSRect(x: 0, y: 0, width: 264, height: 296)
        let window = PetPanel(contentRect: canvas.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = canvas
        window.isOpaque = false
        window.backgroundColor = .clear
        var touches = 0
        var opened = 0
        canvas.onTouch = { touches += 1 }
        canvas.onDoubleClick = { opened += 1 }
        let now = Date()
        let a = AgentActiveTask(threadID: "fixture-a", turnID: "turn", title: "修复桌宠窗口与任务提醒", startedAt: now.addingTimeInterval(-138), updatedAt: now,
            phase: .editing, completedPlanSteps: 2, totalPlanSteps: 5)
        let b = AgentActiveTask(threadID: "fixture-b", turnID: "turn", title: "检查第二个任务的工作状态", startedAt: now.addingTimeInterval(-62), updatedAt: now,
            phase: .searching, completedPlanSteps: nil, totalPlanSteps: nil)
        canvas.codexProgressEnabled = true
        canvas.codexTasks = [b, a]
        func value() -> String { canvas.accessibilityValue() as? String ?? "" }
        @discardableResult func capture(_ name: String) throws -> NSBitmapImageRep {
            canvas.needsDisplay = true
            canvas.displayIfNeeded()
            guard let image = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else {
                throw NSError(domain: "CanvasTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to allocate native render bitmap"])
            }
            canvas.cacheDisplay(in: canvas.bounds, to: image)
            try image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            var opaqueBodyPixels = 0
            for y in 88..<image.pixelsHigh {
                for x in 0..<image.pixelsWide where (image.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 { opaqueBodyPixels += 1 }
            }
            try expect(opaqueBodyPixels > 1000, "Every render must retain the original pet below the bubble")
            return image
        }
        try expect(canvas.petRect.minY == 88 && canvas.petRect.maxY == canvas.bounds.maxY, "The original pet rect must retain 88 pixels of bubble space")
        try expect(value().contains(a.title) && value().contains(AgentTaskPhase.editing.label), "AX must expose the current full title and real stage")
        try expect(value().contains("计划步骤 2/5") && value().contains("任务 1/2"), "AX must expose actual plan steps and carousel position")
        let planned = try capture("work-bubble-plan")
        try expect((planned.colorAt(x: 15, y: 10)?.alphaComponent ?? 0) > 0, "The bubble must fit inside the canvas")
        let gapIsClear = (0..<planned.pixelsWide).allSatisfy { (planned.colorAt(x: $0, y: 85)?.alphaComponent ?? 0) < 0.01 }
        try expect(gapIsClear, "Bubble and original pet must not overlap")

        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 125, y: 260), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        canvas.mouseDown(with: down)
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: 125, y: 260), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
        canvas.mouseUp(with: up)
        try expect(value().contains(b.title) && value().contains("任务 2/2"), "Clicking the working bubble must switch tasks")
        try expect(touches == 0, "Clicking the working bubble must not trigger a touch or XP")
        let busy = try capture("work-bubble-busy")
        try expect(!value().contains("计划步骤"), "No plan must remain indeterminate, with no invented completion")
        try expect(busy.pixelsWide == 264 && busy.pixelsHigh == 296, "The full original canvas must render")

        canvas.say("这是一条临时互动提醒", seconds: 0.2)
        try expect(value().contains("临时互动提醒"), "Temporary speech must take priority")
        let hiddenFrame = canvas.frameIndex
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        try expect(canvas.frameIndex == hiddenFrame, "Invisible previews must not run animation timers")
        canvas.advance() // Offscreen fixtures explicitly tick; visible windows tick automatically.
        try expect(value().contains(b.title), "Working progress must return after temporary speech expires")
        canvas.codexProgressVisible = false
        try expect(value().isEmpty, "Do-not-disturb must clear the full working bubble immediately")
        let hidden = try capture("work-bubble-hidden")
        try expect((hidden.colorAt(x: 15, y: 10)?.alphaComponent ?? 0) < 0.01, "The hidden bubble must not retain any visible background")
        canvas.codexProgressVisible = true
        try expect(value().contains(b.title), "Visibility restoration must resume work progress")
        window.ignoresMouseEvents = true
        RunLoop.current.run(until: Date().addingTimeInterval(4.2))
        canvas.advance()
        try expect(value().contains(a.title), "Click-through must preserve automatic rotation")
        canvas.codexProgressEnabled = false
        try expect(value().isEmpty, "Disconnect must clear working text and accessibility value")
        try expect(canvas.accessibilityPerformPress() && opened == 1 && touches == 0, "The accessible pet button must still open the panel without a touch reward")

        let petDoubleClick = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 125, y: 104), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 3, clickCount: 2, pressure: 1)!
        canvas.mouseDown(with: petDoubleClick)
        try expect(opened == 2 && touches == 0, "Double-clicking the original pet must still open its panel")
        canvas.scale = 0.65
        canvas.frame.size = NSSize(width: 264, height: 208 * canvas.scale + 88)
        canvas.codexProgressEnabled = true
        canvas.codexTasks = [a, b]
        try expect(canvas.petRect.minY == 88, "Small pet sizes must preserve the full bubble space")
        _ = try capture("work-bubble-small-pet")
        // Render the shipped artwork through the same AppKit view used on the desktop.
        let atlasLoadStart = Date()
        let librarian = try SpriteAtlas(url: resources.appendingPathComponent("l3d-spritesheet.png"))
        try expect(Date().timeIntervalSince(atlasLoadStart) < 8, "Shipped atlas must load without per-scanline PNG decoding")
        try expect(librarian.hasActivities, "The shipped librarian must include both requested activity cycles")
        canvas.replaceAtlas(librarian)
        canvas.focused = false
        canvas.play("touch-head", duration: 2)
        try expect(canvas.currentImage === librarian.frames[SpriteState.idle.row][canvas.frameIndex % 6], "Touch uses exact normal artwork, without proportional zoom")
        canvas.focused = true
        canvas.play("touch-face", duration: 2)
        try expect(canvas.currentImage === librarian.writingFrames![canvas.frameIndex % 6], "Touch during work preserves exact writing artwork")
        canvas.play("running", duration: 0.2)
        canvas.scale = 1
        canvas.frame.size = NSSize(width: 264, height: 296)
        canvas.codexTasks = []
        var clickedZone: String?
        canvas.onTouchZone = { zone in
            clickedZone = zone
            canvas.play("touch-" + zone, duration: 2.5) // Same request sent by the store.
        }
        for working in [false, true] {
            canvas.focused = working
            canvas.play(working ? "running" : "idle", duration: 1)
            let point = canvas.convert(NSPoint(x: canvas.petRect.midX, y: canvas.petRect.minY + 120), to: nil)
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 10, clickCount: 1, pressure: 1)!
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 11, clickCount: 1, pressure: 0)!
            canvas.mouseDown(with: down); canvas.mouseUp(with: up)
            try expect(clickedZone == "book" && canvas.lifeAnimation == "touch", "Book hit region must not route to the oversized page-flip sheet")
            let normal = working ? librarian.writingFrames![0] : librarian.frames[SpriteState.idle.row][0]
            try expect(canvas.currentImage === normal, "Real book click keeps exact normal/work artwork")
        }
        canvas.onTouchZone = nil
        canvas.focused = true
        canvas.play("running", duration: 0.2)
        _ = try capture("l3d-writing")
        canvas.focused = false
        canvas.codexTasks = []
        canvas.play("sleeping", duration: 4)
        try expect(canvas.isSleeping, "The shipped librarian must render the duck-sit sleeping pose")
        _ = try capture("l3d-duck-sit-dozing")
        try expect(PetHomeArtwork.images.count == 4, "All four illustrated home props must load for both room and desktop")
        try expect(librarian.blanketFrames?.count == 6, "Shipped lap blanket must be six integrated sleeping frames")
        try expect(librarian.accessories.count == 12, "All four seasonal fabric sets must be packaged")
        let uncovered = canvas.currentImage
        canvas.outfitItems = ["blanket"]
        try expect(canvas.currentImage === librarian.blanketFrames![canvas.frameIndex % 6], "Wearable blanket selects fitted sleeping art")
        canvas.outfitItems = []
        try expect(canvas.currentImage === uncovered, "Removing blanket restores original bowed sleeping pose")
        canvas.homeItems = ["blanket"]
        try expect(canvas.currentImage === librarian.blanketFrames![canvas.frameIndex % 6], "Home blanket also uses integrated lap art")
        canvas.homeItems = ["cushion", "desk", "lamp", "blanket"]
        canvas.outfitItems = ["bow", "scarf", "sleepCap", "blanket"]
        canvas.season = "winter"
        _ = try capture("l3d-cozy-sleep-outfit")
        canvas.focused = true
        canvas.play("running", duration: 0.2)
        canvas.mood = "cheerful"
        _ = try capture("l3d-cozy-work-outfit")
        canvas.beginCarrying()
        _ = try capture("l3d-carry-outfit")
        canvas.finishCarrying()
        _ = try capture("l3d-land-outfit")
        if librarian.hasLifeAnimations {
            canvas.outfitItems = []
            canvas.homeItems = []
            canvas.focused = false
            canvas.play("idle", duration: 1)
            _ = try capture("l3d-scale-normal")
            for action in ["touch", "drink", "eat", "eat-riceBall", "carry"] {
                canvas.play(action, duration: 4)
                try expect(canvas.animatedPetRect == canvas.petRect, "Interactions preserve normal character bounds: " + action)
                _ = try capture("l3d-scale-" + action)
            }
            canvas.scale = 2
            canvas.frame.size = NSSize(width: 528, height: 504)
            for action in SpriteAtlas.lifeRows {
                canvas.play(action, duration: 4)
                _ = try capture("l3d-life-" + action)
            }
            for food in SpriteAtlas.foodRows where librarian.foodFrames[food] != nil {
                canvas.play("eat-" + food, duration: 4)
                _ = try capture("l3d-food-" + food)
            }
        }
        canvas.homeItems = ["blanket"]
        canvas.mood = "calm"
        canvas.scale = 2
        canvas.frame.size = NSSize(width: 528, height: 504)
        for sleeping in [false, true] {
            canvas.focused = !sleeping
            canvas.play(sleeping ? "sleeping" : "running", duration: 30)
            for frame in 0..<6 {
                canvas.advance(at: Date().addingTimeInterval(Double(frame + 1)))
                _ = try capture("fitted-" + (sleeping ? "sleep" : "work") + "-" + String(frame))
            }
        }
        print("PASS: \(assertions) native Canvas assertions — activity sidecar loading, work/idle/sleep transitions, wake interactions, legacy fallback, fixture rendering, bubble click without XP, AX, DND and panel actions")
        print("Fixture previews: \(output.path)")
        window.close()
    }
}
