import AppKit
import UniformTypeIdentifiers

enum SpriteState: String, CaseIterable {
    case idle, runningRight = "running-right", runningLeft = "running-left", waving, jumping, failed, waiting, running, review
    var row: Int { Self.allCases.firstIndex(of: self)! }
    var frameCount: Int { [6, 8, 8, 4, 5, 8, 6, 6, 6][row] }
    var fps: Double { self == .idle ? 5 : (self == .jumping ? 8 : 7) }
}

final class SpriteAtlas {
    let frames: [[NSImage]]
    let looks: [NSImage]
    let fullImage: NSImage
    let writingFrames: [NSImage]?
    let sleepingFrames: [NSImage]?
    let lifeFrames: [String: [NSImage]]
    let foodFrames: [String: [NSImage]]
    let blanketFrames: [NSImage]?
    let accessories: [String: NSImage]
    static let foodRows = ["riceBall", "sandwich", "apple", "cake"]
    static let lifeRows = ["rub-eyes", "stretch", "page-flip", "groom", "yawn", "eat", "drink", "carry", "land", "touch"]
    var hasActivities: Bool { writingFrames != nil && sleepingFrames != nil }
    var hasLifeAnimations: Bool { !lifeFrames.isEmpty }

    private static func decoded(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    init(url: URL) throws {
        guard let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil).flatMap(Self.decoded),
              cg.width == 1536, cg.height == 2288 else {
            throw NSError(domain: "XiaoKe", code: 1, userInfo: [NSLocalizedDescriptionKey: "小可的动画资源缺失或尺寸不正确。"])
        }
        fullImage = image
        func cell(_ row: Int, _ col: Int) -> NSImage {
            let crop = cg.cropping(to: CGRect(x: col * 192, y: row * 208, width: 192, height: 208))!
            return NSImage(cgImage: crop, size: NSSize(width: 192, height: 208))
        }
        frames = SpriteState.allCases.map { state in (0..<state.frameCount).map { cell(state.row, $0) } }
        looks = (0..<16).map { cell(9 + $0 / 8, $0 % 8) }
        let activityURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-activities.png")
        if FileManager.default.fileExists(atPath: activityURL.path) {
            guard let activity = NSImage(contentsOf: activityURL),
                  let cg = activity.cgImage(forProposedRect: nil, context: nil, hints: nil).flatMap(Self.decoded),
                  cg.width == 1152, cg.height == 416 else {
                throw NSError(domain: "XiaoKe", code: 2, userInfo: [NSLocalizedDescriptionKey: "小可的工作与打盹动画尺寸不正确。"])
            }
            func activityRow(_ row: Int) -> [NSImage] {
                (0..<6).map { column in
                    NSImage(cgImage: cg.cropping(to: CGRect(x: column * 192, y: row * 208, width: 192, height: 208))!,
                            size: NSSize(width: 192, height: 208))
                }
            }
            writingFrames = activityRow(0)
            sleepingFrames = activityRow(1)
        } else {
            writingFrames = nil
            sleepingFrames = nil
        }
        let lifeURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-life.png")
        if FileManager.default.fileExists(atPath: lifeURL.path) {
            guard let image = NSImage(contentsOf: lifeURL),
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil).flatMap(Self.decoded),
                  cg.width == 1152, cg.height == 2080 else {
                throw NSError(domain: "XiaoKe", code: 3, userInfo: [NSLocalizedDescriptionKey: "小可的生活动作资源尺寸不正确。"])
            }
            lifeFrames = Dictionary(uniqueKeysWithValues: Self.lifeRows.enumerated().map { row, name in
                (name, (0..<6).map { column in
                    NSImage(cgImage: cg.cropping(to: CGRect(x: column * 192, y: row * 208, width: 192, height: 208))!,
                            size: NSSize(width: 192, height: 208))
                })
            })
        } else { lifeFrames = [:] }
        let foodURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-foods.png")
        if FileManager.default.fileExists(atPath: foodURL.path) {
            guard let image = NSImage(contentsOf: foodURL),
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil).flatMap(Self.decoded),
                  cg.width == 1152, cg.height == 832 else {
                throw NSError(domain: "XiaoKe", code: 4, userInfo: [NSLocalizedDescriptionKey: "小可的食物动作资源尺寸不正确。"])
            }
            foodFrames = Dictionary(uniqueKeysWithValues: Self.foodRows.enumerated().map { row, name in
                (name, (0..<6).map { column in
                    NSImage(cgImage: cg.cropping(to: CGRect(x: column * 192, y: row * 208, width: 192, height: 208))!,
                            size: NSSize(width: 192, height: 208))
                })
            })
        } else { foodFrames = [:] }
        let directory = url.deletingLastPathComponent()
        let blanketURL = directory.appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-blanket.png")
        if FileManager.default.fileExists(atPath: blanketURL.path) {
            guard let image = NSImage(contentsOf: blanketURL),
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil).flatMap(Self.decoded),
                  cg.width == 1152, cg.height == 208 else {
                throw NSError(domain: "XiaoKe", code: 5, userInfo: [NSLocalizedDescriptionKey: "小可的贴合毛毯动画尺寸不正确。"])
            }
            blanketFrames = (0..<6).map { column in
                NSImage(cgImage: cg.cropping(to: CGRect(x: column * 192, y: 0, width: 192, height: 208))!, size: NSSize(width: 192, height: 208))
            }
        } else { blanketFrames = nil }
        var fitted: [String: NSImage] = [:]
        if url.lastPathComponent.hasPrefix("l3d-") {
            for season in ["spring", "summer", "autumn", "winter"] {
                for kind in ["bow", "scarf", "sleepCap"] {
                    let key = season + "-" + kind
                    if let image = NSImage(contentsOf: directory.appendingPathComponent("l3d-accessory-" + key + ".png")) { fitted[key] = image }
                }
            }
        }
        accessories = fitted
    }
}

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class SpriteCanvas: NSView {
    private(set) var atlas: SpriteAtlas
    var onTouch: (() -> Void)?
    var onTouchZone: ((String) -> Void)?
    var homeItems: Set<String> = [] { didSet { if homeItems != oldValue { needsDisplay = true } } }
    var outfitItems: Set<String> = [] { didSet { if outfitItems != oldValue { needsDisplay = true } } }
    var season = "spring" { didSet { if season != oldValue { needsDisplay = true } } }
    var mood = "calm" { didSet { if mood != oldValue { needsDisplay = true } } }
    var onDoubleClick: (() -> Void)?
    var onMoved: ((NSPoint) -> Void)?
    var onFile: ((URL) -> Void)?
    var menuProvider: (() -> NSMenu)?
    var scale: CGFloat = 1 { didSet { if scale != oldValue { needsDisplay = true } } }
    var mouseFollow = true
    var focused = false {
        didSet {
            guard focused != oldValue else { return }
            let now = clock()
            idleSince = now
            nextAmbientAt = now.addingTimeInterval(32)
            // Work is live state, never a long timed animation. Brief interactions may finish.
            if isSleeping || state == .running { stateUntil = nil; lifeAnimation = nil; animationName = nil }
            isSleeping = false
            updateDefaultActivity(at: now)
        }
    }
    var quiet = false
    var codexTasks: [AgentActiveTask] = [] {
        didSet {
            let now = Date()
            bubbleCycler.updateTasks(codexTasks, at: now)
            refreshBubble(at: now)
        }
    }
    var codexProgressEnabled = false {
        didSet {
            let now = Date()
            bubbleCycler.setProgressEnabled(codexProgressEnabled, at: now)
            if codexProgressEnabled { bubbleCycler.updateTasks(codexTasks, at: now) }
            refreshBubble(at: now)
        }
    }
    var codexProgressVisible = true {
        didSet {
            let now = Date()
            bubbleCycler.setProgressVisible(codexProgressVisible, at: now)
            refreshBubble(at: now)
        }
    }
    private(set) var state: SpriteState = .idle
    private(set) var frameIndex = 0
    private(set) var lookIndex: Int?
    private(set) var isSleeping = false
    private(set) var lifeAnimation: String?
    private(set) var animationName: String?
    private(set) var isCarried = false
    private var animationStartedAt = Date.distantPast
    private var nextAmbientAt: Date
    private var ambientIndex = 0
    private var preserveIdleDeadline = false
    private var touchPoint: NSPoint?
    private var pressedTouchZone: String?
    private var touchDates: [Date] = []
    private let clock: () -> Date
    private var idleSince: Date
    private let sleepDelay: TimeInterval = 8
    private var stateUntil: Date?
    private var lastFrame = Date.distantPast
    private var lastPointer = NSPoint.zero
    private var gazeUntil = Date.distantPast
    private var timer: Timer?
    private var dragOrigin: NSPoint?
    private var initialWindowOrigin: NSPoint?
    private var wasDragged = false
    private var bubbleCycler = CodexTaskBubbleCycler()
    private var bubbleDisplay: CodexTaskBubbleDisplay?
    override var isFlipped: Bool { true }

    init(atlas: SpriteAtlas, now: @escaping () -> Date = Date.init) {
        self.atlas = atlas
        clock = now
        idleSince = now()
        nextAmbientAt = now().addingTimeInterval(32)
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 296))
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("桌面伙伴")
        setAccessibilityIdentifier("desktop-pet")
        setAccessibilityHelp("摸摸头、脸或书有不同回应；拖动抱起，松手放下。双击打开陪伴面板，右键打开菜单；点击工作气泡可切换任务。")
        let t = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            guard let self, self.window?.isVisible == true, !self.isHiddenOrHasHiddenAncestor else { return }
            self.advance()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    deinit { timer?.invalidate() }

    var petRect: NSRect {
        NSRect(x: (bounds.width - 192 * scale) / 2, y: bounds.height - 208 * scale,
               width: 192 * scale, height: 208 * scale)
    }
    var animationFPS: Double {
        if let animation = lifeAnimation { return ["eat", "drink"].contains(animation) ? 1.75 : (animation == "carry" ? 4 : 3) }
        if isSleeping { return 1.5 }
        if state == .running && atlas.hasActivities { return 3 }
        return state.fps
    }
    var currentImage: NSImage {
        // Touch feedback must not replace the character with a differently
        // proportioned social sheet. Reuse the exact normal/work artwork;
        // sway, blush and head sparkles provide the interaction feedback.
        if lifeAnimation == "touch" {
            if focused, let frames = atlas.writingFrames { return frames[frameIndex % frames.count] }
            return atlas.frames[SpriteState.idle.row][frameIndex % SpriteState.idle.frameCount]
        }
        if isSleeping, (homeItems.contains("blanket") || outfitItems.contains("blanket")), let frames = atlas.blanketFrames {
            return frames[frameIndex % frames.count]
        }
        if let name = animationName, name.hasPrefix("eat-"),
           let frames = atlas.foodFrames[String(name.dropFirst(4))] { return frames[frameIndex % frames.count] }
        if let animation = lifeAnimation, let frames = atlas.lifeFrames[animation] { return frames[frameIndex % frames.count] }
        if isSleeping, let frames = atlas.sleepingFrames { return frames[frameIndex % frames.count] }
        if state == .running, let frames = atlas.writingFrames { return frames[frameIndex % frames.count] }
        return lookIndex.map { atlas.looks[$0] } ?? atlas.frames[state.row][frameIndex % state.frameCount]
    }

    func replaceAtlas(_ atlas: SpriteAtlas) {
        self.atlas = atlas
        headAnchorCache.removeAll()
        isSleeping = false
        lifeAnimation = nil
        animationName = nil
        isCarried = false
        stateUntil = nil
        idleSince = clock()
        nextAmbientAt = clock().addingTimeInterval(32)
        frameIndex = 0
        lookIndex = nil
        lastFrame = .distantPast
        needsDisplay = true
    }

    func play(_ name: String, duration: Double = 2) {
        // A late store update must never interrupt a drag in progress.
        guard !isCarried || name == "carry" else { return }
        let key: String?
        if name.hasPrefix("eat-") { key = "eat" }
        else if name.hasPrefix("drink-") { key = "drink" }
        else if name.hasPrefix("touch-") || name == "dodge" { key = "touch" }
        else { key = SpriteAtlas.lifeRows.contains(name) ? name : nil }
        lifeAnimation = key
        animationName = name
        let mapped = name == "celebrating" ? "jumping" : (name == "sleeping" ? "idle" : name)
        state = SpriteState(rawValue: mapped) ?? (key == "page-flip" ? .review : .idle)
        let now = clock()
        animationStartedAt = now
        idleSince = now
        preserveIdleDeadline = false
        isSleeping = name == "sleeping" && atlas.hasActivities && !focused
        if name == "sleeping" && focused { state = .running }
        frameIndex = 0
        lookIndex = nil
        stateUntil = now.addingTimeInterval(max(0.2, duration))
        lastFrame = now
        needsDisplay = true
    }

    /// Coordinates are local to the canvas, so touch targets scale with the pet.
    func touchZone(at point: NSPoint) -> String? {
        guard petRect.contains(point) else { return nil }
        let x = (point.x - petRect.minX) / scale
        let y = (point.y - petRect.minY) / scale
        guard (38...154).contains(x) else { return nil }
        if isSleeping {
            if y < 99 { return "head" }
            if y < 147 { return "face" }
        } else {
            if y < 49 { return "head" }
            if y < 96 { return "face" }
        }
        return "book"
    }

    private func reactToTouch(at point: NSPoint) {
        guard let zone = pressedTouchZone ?? touchZone(at: point) else { return }
        let now = clock()
        touchDates = touchDates.filter { now.timeIntervalSince($0) < 3 }
        touchDates.append(now)
        play(touchDates.count >= 4 ? "dodge" : "touch-" + zone, duration: 2)
        if let onTouchZone { onTouchZone(zone) } else { onTouch?() }
    }

    // These entry points keep native mouse behavior and synthetic event tests identical.
    func beginCarrying() {
        guard !isCarried else { return }
        isSleeping = false
        isCarried = true
        play("carry", duration: 3600)
        needsDisplay = true
    }

    func finishCarrying() {
        guard isCarried else { return }
        isCarried = false
        play("land", duration: 2.2)
    }

    func say(_ text: String, seconds: Double = 7) {
        let now = Date()
        bubbleCycler.showMessage(text, seconds: seconds, at: now)
        refreshBubble(at: now)
        needsDisplay = true
    }

    private func updateDefaultActivity(at now: Date) {
        guard stateUntil == nil, dragOrigin == nil, !isCarried else { return }
        let desired: SpriteState = focused ? .running : .idle
        let sleeping = !focused && atlas.hasActivities && now.timeIntervalSince(idleSince) >= sleepDelay
        if state != desired || isSleeping != sleeping {
            if sleeping && !isSleeping { nextAmbientAt = now.addingTimeInterval(55) }
            state = desired
            lifeAnimation = nil
            animationName = nil
            isSleeping = sleeping
            frameIndex = 0
            lookIndex = nil
            lastFrame = now
            needsDisplay = true
        }
    }

    private func wakeForInteraction() {
        let now = clock()
        idleSince = now
        if isSleeping {
            isSleeping = false
            stateUntil = nil
            lifeAnimation = nil
            animationName = nil
            state = focused ? .running : .idle
            frameIndex = 0
            lookIndex = nil
            lastFrame = now
            if !focused && atlas.hasLifeAnimations { play("yawn", duration: 2) }
            needsDisplay = true
        }
    }

    func advance(at date: Date? = nil) {
        let now = date ?? clock()
        if let deadline = stateUntil, now >= deadline, dragOrigin == nil {
            stateUntil = nil
            isSleeping = false
            lifeAnimation = nil
            animationName = nil
            if !preserveIdleDeadline { idleSince = now }
            preserveIdleDeadline = false
            state = focused ? .running : .idle
            frameIndex = 0
            lastFrame = now
            needsDisplay = true
        }
        updateDefaultActivity(at: now)
        if atlas.hasLifeAnimations && !quiet && stateUntil == nil && dragOrigin == nil && now >= nextAmbientAt {
            let previousIdle = idleSince
            let actions = focused ? ["page-flip", "stretch", "groom", "page-flip"] : ["rub-eyes", "yawn", "groom", "stretch"]
            let action = actions[ambientIndex % actions.count]
            ambientIndex += 1
            play(action, duration: 2.1)
            if !focused { idleSince = previousIdle; preserveIdleDeadline = true }
            nextAmbientAt = now.addingTimeInterval(focused ? 32 : 55)
        }
        if now.timeIntervalSince(lastFrame) >= 1 / animationFPS {
            let count = lifeAnimation != nil ? 6 : state.frameCount
            let nextFrame = lifeAnimation != nil && !isCarried ? min(frameIndex + 1, count - 1) : (frameIndex + 1) % count
            if frameIndex != nextFrame { frameIndex = nextFrame; needsDisplay = true }
            lastFrame = now
        }
        if mouseFollow && !quiet && !isSleeping && lifeAnimation == nil && state == .idle && dragOrigin == nil,
           let w = window {
            let p = NSEvent.mouseLocation
            if hypot(p.x - lastPointer.x, p.y - lastPointer.y) > 4 {
                lastPointer = p
                gazeUntil = now.addingTimeInterval(1.2)
            }
            let head = NSPoint(x: w.frame.minX + petRect.midX,
                               y: w.frame.minY + bounds.height - petRect.minY - 70 * scale)
            let dx = p.x - head.x, dy = p.y - head.y
            if now < gazeUntil && hypot(dx, dy) < 650 && hypot(dx, dy) > 25 {
                let angle = atan2(dx, dy)
                let idx = (Int((angle / (Double.pi / 8)).rounded()) + 16) % 16
                if lookIndex != idx { lookIndex = idx; needsDisplay = true }
            } else if lookIndex != nil { lookIndex = nil; needsDisplay = true }
        } else if lookIndex != nil { lookIndex = nil; needsDisplay = true }
        refreshBubble(at: now)
    }

    private func refreshBubble(at now: Date) {
        let next = bubbleCycler.display(at: now)
        if next != bubbleDisplay {
            bubbleDisplay = next
            setAccessibilityValue(next?.accessibilityValue ?? "")
            needsDisplay = true
        }
        // Only the indeterminate busy marker needs continuous movement.
        if case .task(let content) = next, content.planFraction == nil { setNeedsDisplay(workBubbleRect) }
    }

    private var workBubbleRect: NSRect {
        let width = min(bounds.width - 14, 250)
        return NSRect(x: (bounds.width - width) / 2, y: max(4, petRect.minY - 84), width: width, height: 78)
    }

    private func drawBubbleBackground(_ rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 15, yRadius: 15)
        NSColor(calibratedRed: 1.0, green: 0.98, blue: 0.96, alpha: 0.98).setFill()
        path.fill()
        NSColor(calibratedRed: 0.79, green: 0.72, blue: 0.88, alpha: 0.95).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawWorkBubble(_ content: CodexTaskBubbleContent, at now: Date) {
        let rect = workBubbleRect
        drawBubbleBackground(rect)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let bodyColor = NSColor(calibratedRed: 0.32, green: 0.27, blue: 0.39, alpha: 1)
        let accent = NSColor(calibratedRed: 0.47, green: 0.35, blue: 0.66, alpha: 1)
        func drawLine(_ text: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor,
                      alignment: NSTextAlignment = .left, width: CGFloat? = nil) {
            let p = paragraph.mutableCopy() as! NSMutableParagraphStyle
            p.alignment = alignment
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color, .paragraphStyle: p]
            (text as NSString).draw(in: NSRect(x: rect.minX + 11, y: rect.minY + y,
                width: width ?? rect.width - 22, height: 17), withAttributes: attributes)
        }
        drawLine(content.title, y: 8, size: 12, weight: .semibold, color: accent)
        drawLine("\(content.phaseLabel) · 已用\(content.elapsedLabel)", y: 27, size: 11, weight: .medium, color: bodyColor)
        drawLine(content.planLabel ?? "忙碌中", y: 46, size: 10, weight: .regular, color: bodyColor, width: 128)
        let clickable = content.taskCount > 1 && window?.ignoresMouseEvents != true
        drawLine(content.indexLabel + (clickable ? " · 点击切换" : ""), y: 46, size: 10, weight: .regular,
                 color: bodyColor, alignment: .right)
        let track = NSRect(x: rect.minX + 11, y: rect.maxY - 8, width: rect.width - 22, height: 3)
        NSColor(calibratedRed: 0.91, green: 0.87, blue: 0.95, alpha: 1).setFill()
        NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
        let fill: NSRect
        if let fraction = content.planFraction {
            fill = NSRect(x: track.minX, y: track.minY, width: track.width * fraction, height: track.height)
        } else {
            let phase = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
            let segmentWidth = track.width * 0.24
            fill = NSIntersectionRect(track, NSRect(x: track.minX - segmentWidth + phase * (track.width + segmentWidth),
                y: track.minY, width: segmentWidth, height: track.height))
        }
        if fill.width > 0 { accent.setFill(); NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill() }
    }

    var animatedPetRect: NSRect {
        var rect = petRect
        let elapsed = max(0, clock().timeIntervalSince(animationStartedAt))
        if isCarried {
            // Translate only: picking up must never shrink, stretch or zoom.
            rect.origin.x += sin(elapsed * 4) * 1.2 * scale
        } else if animationName == "dodge" {
            rect.origin.x += sin(min(1, elapsed / 1.8) * .pi) * 14 * scale
        } else if lifeAnimation == "land" && elapsed < 0.5 {
            // Landing uses its own consistently sized art, without body squash.
            rect.origin.y += sin(elapsed / 0.5 * .pi) * 1.5 * scale
        } else if animationName == "touch-face" {
            rect.origin.x += sin(elapsed * 5) * 1.2 * scale
        }
        return rect
    }

    private var seasonColor: NSColor {
        switch season {
        case "summer": return NSColor(calibratedRed: 0.48, green: 0.75, blue: 0.73, alpha: 1)
        case "autumn": return NSColor(calibratedRed: 0.87, green: 0.62, blue: 0.38, alpha: 1)
        case "winter": return NSColor(calibratedRed: 0.58, green: 0.68, blue: 0.85, alpha: 1)
        default: return NSColor(calibratedRed: 0.82, green: 0.62, blue: 0.76, alpha: 1)
        }
    }

    private func drawHome(foreground: Bool = false) {
        guard !isCarried else { return }
        func draw(_ name: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
            guard homeItems.contains(name), let image = PetHomeArtwork.images[name] else { return }
            image.draw(in: NSRect(x: petRect.minX + x * scale, y: petRect.minY + y * scale,
                                 width: width * scale, height: height * scale),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                       hints: [.interpolation: NSImageInterpolation.high])
        }
        if foreground {
            // The tabletop is in front of the lower dress; the book and hands
            // remain above it. Open space between the legs stays transparent.
            if focused { draw("desk", 19, 123, 154, 77) }
            if !isSleeping { draw("blanket", 6, 183, 40, 21) }
        } else {
            if !focused { draw("cushion", 34, 146, 124, 59) }
            let base: CGFloat = focused && homeItems.contains("desk") ? 132 : 200
            draw("lamp", 150, base - 64, 38, 64)
        }
    }

    private var headAnchorCache: [ObjectIdentifier: NSPoint] = [:]

    /// Track the opaque crown in each actual frame instead of a global pose offset.
    private func crownAnchor(for image: NSImage) -> NSPoint {
        let key = ObjectIdentifier(image)
        if let cached = headAnchorCache[key] { return cached }
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return NSPoint(x: 96, y: 7) }
        let bitmap = NSBitmapImageRep(cgImage: cg)
        var top = 208
        for y in 0..<min(160, bitmap.pixelsHigh) {
            let count = (40..<min(152, bitmap.pixelsWide)).reduce(0) { $0 + ((bitmap.colorAt(x: $1, y: y)?.alphaComponent ?? 0) > 0.65 ? 1 : 0) }
            if count >= 7 { top = y; break }
        }
        var left = 192, right = 0
        for y in min(top + 12, 207)..<min(top + 34, 208) {
            for x in 35..<min(157, bitmap.pixelsWide) where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.65 {
                left = min(left, x); right = max(right, x)
            }
        }
        let point = NSPoint(x: left < right ? CGFloat(left + right) / 2 : 96, y: CGFloat(min(top, 150)))
        headAnchorCache[key] = point
        return point
    }

    private func drawAccessories(in rect: NSRect) {
        guard !atlas.accessories.isEmpty else { return }
        let crown = crownAnchor(for: currentImage)
        let sx = rect.width / 192, sy = rect.height / 208
        func draw(_ kind: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat? = nil) {
            guard outfitItems.contains(kind), let image = atlas.accessories[season + "-" + kind] else { return }
            let h = height ?? width * image.size.height / max(1, image.size.width)
            image.draw(in: NSRect(x: rect.minX + x * sx, y: rect.minY + y * sy, width: width * sx, height: h * sy),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                       hints: [.interpolation: NSImageInterpolation.high])
        }
        // A full curved band seats on the crown. The bow moves to the braid when
        // paired with the hat, so neither accessory floats on top of the other.
        draw("sleepCap", x: crown.x - 34, y: crown.y - 5, width: 70, height: 43)
        // Neckwear stays compact at the collar. Raised hands, food and the book
        // are in front of it; never draw a detached tail over those objects.
        let neck: CGFloat
        if isSleeping { neck = crown.y + 76 }
        else if let action = lifeAnimation, atlas.lifeFrames[action] != nil {
            if ["eat", "drink", "carry"].contains(action) { neck = crown.y + 73 }
            else if action == "touch" { neck = crown.y + 77 }
            else if action == "land" { neck = crown.y + 73 }
            else { neck = crown.y + 86 }
        } else { neck = crown.y + 77 }
        let bowY = outfitItems.contains("sleepCap") ? neck + 8 : crown.y + 34
        draw("bow", x: crown.x + (outfitItems.contains("sleepCap") ? 34 : 26), y: bowY, width: 13)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: rect.minX + (crown.x - 14) * sx, y: rect.minY + neck * sy,
                                 width: 28 * sx, height: (lifeAnimation == "eat" || lifeAnimation == "drink" ? 7 : 12) * sy)).addClip()
        draw("scarf", x: crown.x - 13, y: neck, width: 26, height: 12)
        NSGraphicsContext.restoreGraphicsState()
        // The blanket is part of the six sleeping frames, with hands above its
        // folds and knees beneath it. There is intentionally no foreground polygon.
    }

    private func drawMood(in rect: NSRect) {
        guard !quiet && !isCarried else { return }
        let sx = rect.width / 192, sy = rect.height / 208
        func at(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        if mood == "shy" || animationName == "touch-face" {
            NSColor(calibratedRed: 0.97, green: 0.63, blue: 0.66, alpha: 0.32).setFill()
            let y: CGFloat = isSleeping ? 119 : 74
            for x: CGFloat in [76, 110] { NSBezierPath(ovalIn: NSRect(origin: at(x, y), size: NSSize(width: 10 * sx, height: 4 * sy))).fill() }
        }
        if animationName == "touch-head" {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10 * sx), .foregroundColor: seasonColor]
            ("♥" as NSString).draw(at: at(48, 47), withAttributes: attributes)
            ("♥" as NSString).draw(at: at(138, 37), withAttributes: attributes)
        }
        let mark: String?
        switch mood {
        case "cheerful": mark = "✦"
        case "hungry": mark = "🍪"
        case "sleepy": mark = "z"
        default: mark = nil
        }
        if let mark {
            let color = mood == "hungry" ? NSColor(calibratedRed: 0.78, green: 0.57, blue: 0.36, alpha: 0.75) : seasonColor.withAlphaComponent(0.85)
            (mark as NSString).draw(at: at(145, isSleeping ? 116 : 69), withAttributes: [
                .font: NSFont.systemFont(ofSize: 12 * sx, weight: .semibold), .foregroundColor: color])
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        if dirtyRect.intersects(petRect.insetBy(dx: -10, dy: -10)) {
        drawHome()
        let displayRect = animatedPetRect
        currentImage.draw(in: displayRect, from: .zero, operation: .sourceOver, fraction: 1,
                          respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        drawAccessories(in: displayRect)
        drawHome(foreground: true)
        drawMood(in: displayRect)
        }
        if case .task(let content) = bubbleDisplay {
            drawWorkBubble(content, at: Date())
        } else if case .message(let text) = bubbleDisplay {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor(calibratedRed: 0.32, green: 0.27, blue: 0.39, alpha: 1),
                .paragraphStyle: paragraph
            ]
            let width = min(bounds.width - 14, 250)
            let textSize = (text as NSString).boundingRect(with: NSSize(width: width - 24, height: 52),
                options: [.usesLineFragmentOrigin], attributes: attrs).size
            let r = NSRect(x: (bounds.width - width) / 2, y: max(4, petRect.minY - textSize.height - 27),
                           width: width, height: min(66, textSize.height + 18))
            drawBubbleBackground(r)
            (text as NSString).draw(in: r.insetBy(dx: 12, dy: 8), withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let now = Date()
        refreshBubble(at: now)
        if case .task = bubbleDisplay, workBubbleRect.contains(convert(event.locationInWindow, from: nil)) {
            dragOrigin = nil
            initialWindowOrigin = nil
            wasDragged = false
            _ = bubbleCycler.nextTask(at: now)
            refreshBubble(at: now)
            return
        }
        touchPoint = convert(event.locationInWindow, from: nil)
        pressedTouchZone = touchPoint.flatMap { touchZone(at: $0) }
        guard pressedTouchZone != nil else { return }
        wakeForInteraction()
        if event.clickCount == 2 { onDoubleClick?(); return }
        dragOrigin = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        initialWindowOrigin = window?.frame.origin
        wasDragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragOrigin, let origin = initialWindowOrigin, let w = window else { return }
        let p = w.convertPoint(toScreen: event.locationInWindow)
        let dx = p.x - start.x, dy = p.y - start.y
        if hypot(dx, dy) > 4 { wasDragged = true }
        if wasDragged {
            beginCarrying()
            lookIndex = nil
            w.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
            needsDisplay = true
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard dragOrigin != nil else { return }
        dragOrigin = nil
        initialWindowOrigin = nil
        if wasDragged, let w = window {
            if let screen = NSScreen.screens.first(where: { $0.frame.intersects(w.frame) }) ?? NSScreen.main {
                let r = screen.visibleFrame
                w.setFrameOrigin(NSPoint(x: min(max(w.frame.minX, r.minX), r.maxX - w.frame.width),
                                        y: min(max(w.frame.minY, r.minY), r.maxY - w.frame.height)))
            }
            onMoved?(w.frame.origin)
            finishCarrying()
        } else if let touchPoint { reactToTouch(at: touchPoint) }
        touchPoint = nil
        pressedTouchZone = nil
    }
    override func rightMouseDown(with event: NSEvent) {
        wakeForInteraction()
        if let m = menuProvider?() { NSMenu.popUpContextMenu(m, with: event, for: self) }
    }
    override func accessibilityPerformPress() -> Bool {
        guard let onDoubleClick else { return false }
        wakeForInteraction()
        onDoubleClick()
        return true
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?.first as? URL else { return false }
        onFile?(url)
        return true
    }
}

/// Shared illustrated props used by the desktop, room preview and item cards.
enum PetHomeArtwork {
    static let images: [String: NSImage] = {
        var result: [String: NSImage] = [:]
        for name in ["cushion", "desk", "lamp", "blanket"] {
            let url = Bundle.main.url(forResource: "home-" + name, withExtension: "png")
                ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/home-" + name + ".png")
            if let image = NSImage(contentsOf: url) { result[name] = image }
        }
        return result
    }()
}
