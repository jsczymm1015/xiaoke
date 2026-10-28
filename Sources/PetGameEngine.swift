import Foundation

/// Deterministic rules shared by the playroom and its tests. Time is active play time only.
struct PetGameRound: Equatable {
    let kind: PetGameKind
    private(set) var elapsed: TimeInterval = 0
    private(set) var score = 0
    private(set) var misses = 0
    private(set) var roundNumber = 1
    private(set) var roundElapsed: TimeInterval = 0
    private(set) var targetIndex = 0
    private(set) var selectedIndex: Int?
    private(set) var outcome: Bool?
    private(set) var basketX: Double = 0.5
    private(set) var starX: Double = 0.5
    private(set) var starProgress: Double = 0
    private var resultAge: TimeInterval = 0
    private var randomState: UInt64

    static let duration: TimeInterval = 60
    var remaining: TimeInterval { max(0, Self.duration - elapsed) }
    var isFinished: Bool { elapsed >= Self.duration }
    var previewDuration: TimeInterval { kind == .cookie ? 1.6 : 1.2 }
    var isPreviewing: Bool { kind != .stars && outcome == nil && roundElapsed < previewDuration }
    var canChoose: Bool { !isFinished && kind != .stars && !isPreviewing && outcome == nil }
    var tileCount: Int { kind == .hands ? 2 : 9 }

    init(kind: PetGameKind, seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        self.kind = kind
        randomState = seed == 0 ? 1 : seed
        prepareTarget()
    }

    mutating func moveBasket(to position: Double) {
        guard position.isFinite, !isFinished else { return }
        basketX = min(0.92, max(0.08, position))
    }

    @discardableResult mutating func choose(_ index: Int) -> Bool {
        guard canChoose, (0..<tileCount).contains(index) else { return false }
        selectedIndex = index
        outcome = index == targetIndex
        if outcome == true { score += kind == .cookie ? 3 : 2 }
        else { misses += 1 }
        resultAge = 0
        return true
    }

    mutating func advance(by delta: TimeInterval) {
        guard delta.isFinite, delta > 0, !isFinished else { return }
        var left = min(delta, remaining)
        elapsed += left
        // Small deterministic steps preserve round boundaries when the UI drops a frame.
        while left > 0.000_001 {
            let step = min(left, 0.05)
            left -= step
            roundElapsed += step
            if kind == .stars {
                starProgress += step / 2.4
                if starProgress >= 1 - 0.000_001 {
                    if abs(basketX - starX) <= 0.15 { score += 3; outcome = true }
                    else { misses += 1; outcome = false }
                    roundNumber += 1
                    starProgress = 0
                    roundElapsed = 0
                    starX = 0.12 + randomUnit() * 0.76
                }
            } else if outcome != nil {
                resultAge += step
                if resultAge >= 0.8 { nextRound() }
            } else if roundElapsed >= previewDuration + 3.5 {
                outcome = false
                selectedIndex = nil
                misses += 1
                resultAge = 0
            }
        }
        score = min(kind.maximumScore, score)
    }

    private mutating func nextRound() {
        roundNumber += 1
        roundElapsed = 0
        resultAge = 0
        outcome = nil
        selectedIndex = nil
        prepareTarget()
    }

    private mutating func prepareTarget() {
        targetIndex = Int(randomUnit() * Double(kind == .hands ? 2 : 9))
        starX = 0.12 + randomUnit() * 0.76
    }

    private mutating func randomUnit() -> Double {
        randomState = randomState &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(randomState >> 11) / Double(UInt64(1) << 53)
    }
}
