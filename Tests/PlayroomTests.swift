import Foundation

private struct PlayroomFailure: Error, CustomStringConvertible { let description: String }

@main struct PlayroomTests {
    @MainActor static func main() throws {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            checks += 1
            if !condition() { throw PlayroomFailure(description: message) }
        }

        var star = PetGameRound(kind: .stars, seed: 14)
        let startX = star.starX
        try expect((0.12...0.88).contains(startX), "stars spawn inside reachable playfield")
        star.moveBasket(to: startX)
        star.advance(by: 2.4)
        try expect(star.score == 3 && star.roundNumber == 2, "basket catches a falling star once")
        try expect(star.starX != startX, "next falling star changes position")
        star.moveBasket(to: star.starX > 0.5 ? 0.08 : 0.92)
        star.advance(by: 2.4)
        try expect(star.score == 3 && star.misses == 1, "misplaced basket misses instead of auto scoring")
        star.moveBasket(to: -.infinity)
        try expect(star.basketX.isFinite, "nonfinite input ignored")
        star.moveBasket(to: 15)
        try expect(star.basketX == 0.92, "basket clamped at right edge")
        star.moveBasket(to: -15)
        try expect(star.basketX == 0.08, "basket clamped at left edge")
        try expect(!star.choose(0), "clicking memory targets cannot score in stars")

        var hands = PetGameRound(kind: .hands, seed: 29)
        try expect(hands.isPreviewing && !hands.canChoose, "hands show target before guessing")
        try expect(!hands.choose(hands.targetIndex) && hands.score == 0, "preview cannot be farmed")
        hands.advance(by: 1.21)
        try expect(hands.canChoose && !hands.isPreviewing, "hands become selectable after preview")
        try expect(!hands.choose(2) && !hands.choose(-1), "invalid hand indices ignored")
        let correctHand = hands.targetIndex
        try expect(hands.choose(correctHand) && hands.score == 2, "correct hand scores two")
        try expect(!hands.choose(correctHand) && hands.score == 2, "same reveal cannot score twice")
        hands.advance(by: 0.81)
        try expect(hands.roundNumber == 2 && hands.isPreviewing && hands.outcome == nil, "hands prepare a new preview after result")
        hands.advance(by: 1.3)
        _ = hands.choose(1 - hands.targetIndex)
        try expect(hands.misses == 1 && hands.score == 2 && hands.outcome == false, "wrong hand gives feedback without points")

        var cookie = PetGameRound(kind: .cookie, seed: 61)
        try expect(cookie.tileCount == 9 && (0..<9).contains(cookie.targetIndex), "cookie board has nine valid positions")
        cookie.advance(by: 1.61)
        try expect(!cookie.choose(9), "out-of-board cookie choice rejected")
        try expect(cookie.choose(cookie.targetIndex) && cookie.score == 3, "finding cookie scores three")
        cookie.advance(by: 6.1)
        try expect(cookie.misses >= 1, "unanswered round times out")
        var replayA = PetGameRound(kind: .cookie, seed: 17)
        var replayB = PetGameRound(kind: .cookie, seed: 17)
        replayA.advance(by: 13); replayB.advance(by: 13)
        try expect(replayA == replayB, "seeded rounds reproduce timing and targets")
        let beforeBadTime = replayA
        replayA.advance(by: .nan); replayA.advance(by: .infinity); replayA.advance(by: -100)
        try expect(replayA == beforeBadTime, "invalid clock deltas ignored")
        replayA.advance(by: 1000)
        try expect(replayA.isFinished && replayA.elapsed == 60 && replayA.remaining == 0, "game ends at exactly sixty active seconds")
        let finalGame = replayA
        replayA.advance(by: 20); _ = replayA.choose(replayA.targetIndex)
        try expect(replayA == finalGame, "finished game ignores input and extra ticks")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xiaoke-playroom-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var now = Date(timeIntervalSince1970: 1_790_000_000)
        let store = CompanionStore(directory: directory, now: { now })
        let controller = PetPlayroomController()
        store.setCompanionWorking(true)
        controller.start(store: store, at: now)
        try expect(controller.phase == .ready && controller.round == nil, "working pet cannot start a game")
        store.setCompanionWorking(false)
        controller.selectedKind = .stars
        controller.start(store: store, at: now)
        try expect(controller.phase == .playing, "explicit start begins game")
        for _ in 0..<40 {
            controller.moveBasket(to: controller.round!.starX)
            now.addTimeInterval(0.25); controller.advance(store: store, at: now)
        }
        try expect(controller.round!.elapsed == 10 && controller.round!.score > 0, "controller advances live game and allows input")
        controller.pause(reason: "test", store: store, at: now)
        let paused = controller.round
        now.addTimeInterval(100)
        controller.advance(store: store, at: now)
        controller.moveBasket(to: 0.9)
        controller.choose(0)
        try expect(controller.phase == .paused && controller.round == paused, "paused game freezes time and controls")
        controller.resume(store: store, at: now)
        now.addTimeInterval(0.25); controller.advance(store: store, at: now)
        try expect(controller.round!.elapsed == 10.25, "resume excludes all paused time")
        store.setCompanionWorking(true)
        now.addTimeInterval(1); controller.advance(store: store, at: now)
        try expect(controller.phase == .paused && controller.round!.elapsed == 10.25, "work automatically freezes game")
        controller.resume(store: store, at: now)
        try expect(controller.phase == .paused, "cannot resume during work")
        store.setCompanionWorking(false)
        controller.resume(store: store, at: now)
        for _ in 0..<199 {
            controller.moveBasket(to: controller.round!.starX)
            now.addTimeInterval(0.25); controller.advance(store: store, at: now)
        }
        try expect(controller.phase == .finished && controller.resultSaved, "sixty active seconds submit a valid core session")
        try expect(store.gameBestScore(.stars) == controller.round!.score, "saved best equals completed score")
        try expect(store.state.life.gamePlayCounts[PetGameKind.stars.rawValue] == 1, "one result is recorded")
        let stats = store.state.stats
        now.addTimeInterval(200); controller.advance(store: store, at: now)
        try expect(store.state.stats == stats && store.state.life.gamePlayCounts[PetGameKind.stars.rawValue] == 1, "extra ticks cannot reward twice")

        controller.select(.hands)
        try expect(controller.phase == .ready && controller.round == nil && controller.selectedKind == .hands, "changing game clears old result display")
        controller.start(store: store, at: now)
        controller.select(.cookie)
        try expect(controller.selectedKind == .hands, "active game cannot be replaced by game tabs")
        now.addTimeInterval(1000); controller.advance(store: store, at: now)
        try expect(controller.round!.elapsed == 0.25, "machine sleep does not complete an unattended game")
        controller.finishEarly(store: store)
        try expect(controller.phase == .ready && controller.round == nil, "ending early clears active round")
        try expect(store.state.life.gamePlayCounts[PetGameKind.stars.rawValue] == 1, "early ending creates no record or reward")
        controller.selectedKind = .cookie
        controller.start(store: store, at: now)
        try expect(controller.round!.kind == .cookie && controller.round!.score == 0, "new game starts independently")
        controller.pause(reason: "test import", store: store, at: now)
        let exported = directory.appendingPathComponent("import-test.json")
        try store.exportState(to: exported)
        try store.importState(from: exported)
        controller.resume(store: store, at: now)
        try expect(controller.phase == .ready && controller.round == nil, "imported state invalidates stale game before resuming")
        try expect(controller.notice != nil, "invalidated game explains that a new round is needed")
        controller.start(store: store, at: now)
        try expect(controller.phase == .playing && controller.notice == nil, "new session works after import")
        controller.finishEarly(store: store)
        print("PASS \(checks) playroom rules and session assertions")
    }
}
