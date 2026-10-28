import Foundation
import Combine

@MainActor
final class PetPlayroomController: ObservableObject {
    enum Phase { case ready, playing, paused, finished }
    @Published var selectedKind: PetGameKind = .stars
    @Published private(set) var round: PetGameRound?
    @Published private(set) var phase: Phase = .ready
    @Published private(set) var pauseReason = ""
    @Published private(set) var resultSaved = false
    @Published private(set) var notice: String?
    private var sessionID: UUID?
    private var lastTick: Date?
    var isSessionOpen: Bool { phase == .playing || phase == .paused }

    func select(_ kind: PetGameKind) {
        guard !isSessionOpen, kind != selectedKind else { return }
        selectedKind = kind
        round = nil
        phase = .ready
        resultSaved = false
        notice = nil
    }

    func start(store: CompanionStore, at now: Date = Date()) {
        guard !store.companionWorking else { return }
        if let sessionID { store.cancelGame(sessionID: sessionID) }
        sessionID = store.beginGame(selectedKind)
        round = PetGameRound(kind: selectedKind)
        phase = .playing
        pauseReason = ""
        notice = nil
        resultSaved = false
        lastTick = now
    }

    func advance(store: CompanionStore, at now: Date = Date()) {
        guard phase == .playing, var game = round else { return }
        if store.companionWorking {
            if let sessionID { store.pauseGame(sessionID: sessionID) }
            phase = .paused
            pauseReason = "小可在工作"
            lastTick = nil
            return
        }
        let delta = now.timeIntervalSince(lastTick ?? now)
        lastTick = now
        // Machine sleep or a suspended event loop never consumes a whole game.
        game.advance(by: min(0.25, max(0, delta)))
        round = game
        if game.isFinished {
            phase = .finished
            lastTick = nil
            if let sessionID {
                resultSaved = store.recordGameResult(kind: game.kind, score: game.score, sessionID: sessionID)
            }
            sessionID = nil
        }
    }

    func pause(reason: String, store: CompanionStore, at now: Date = Date()) {
        guard phase == .playing else { return }
        advance(store: store, at: now)
        guard phase == .playing else { return }
        if let sessionID { store.pauseGame(sessionID: sessionID) }
        phase = .paused
        pauseReason = reason
        lastTick = nil
    }

    func resume(store: CompanionStore, at now: Date = Date()) {
        guard phase == .paused, !store.companionWorking, let sessionID else { return }
        guard store.resumeGame(sessionID: sessionID) else {
            finishEarly(store: store)
            notice = "这局已经结束，重新开始一分钟吧。"
            return
        }
        phase = .playing
        pauseReason = ""
        lastTick = now
    }

    func finishEarly(store: CompanionStore) {
        if let sessionID { store.cancelGame(sessionID: sessionID) }
        sessionID = nil
        round = nil
        phase = .ready
        lastTick = nil
        pauseReason = ""
        notice = nil
    }

    func moveBasket(to x: Double) {
        guard phase == .playing else { return }
        round?.moveBasket(to: x)
    }

    func choose(_ index: Int) {
        guard phase == .playing else { return }
        _ = round?.choose(index)
    }
}
