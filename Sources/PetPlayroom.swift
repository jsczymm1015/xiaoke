import AppKit
import SwiftUI
import Combine

@MainActor
struct PetPlayroom: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject var controller: PetPlayroomController
    let isWorking: Bool
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                ForEach(PetGameKind.allCases) { kind in
                    let selected = controller.selectedKind == kind
                    Button { controller.select(kind) } label: {
                        VStack(spacing: 7) {
                            Text(kind.emoji).font(.system(size: 28))
                            Text(kind.title).font(.system(size: 12, weight: .semibold, design: .rounded))
                            Text("最高 \(store.gameBestScore(kind)) 分").font(.caption2)
                        }.frame(maxWidth: .infinity).padding(.vertical, 25).padding(.horizontal, 15)
                            .foregroundStyle(selected ? Color.white : CompanionTheme.accent)
                            .background(selected ? CompanionTheme.accent : CompanionTheme.surfaceRaised,
                                        in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13)
                                .stroke(selected ? Color.clear : CompanionTheme.border.opacity(0.8)))
                            .shadow(color: selected ? CompanionTheme.accent.opacity(0.17) : .clear, radius: 6, y: 3)
                    }.buttonStyle(UndimmedGameButtonStyle())
                        .disabled(controller.isSessionOpen)
                        .accessibilityLabel("\(kind.title)，最高\(store.gameBestScore(kind))分")
                        .accessibilityValue(selected ? "已选择" : "未选择")
                }
            }
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(controller.selectedKind.title).font(.system(size: 21, weight: .bold, design: .rounded))
                        Text(instructions).font(.callout).foregroundStyle(CompanionTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(timeText).font(.system(size: 27, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("\(controller.round?.score ?? 0) 分").font(.callout).foregroundStyle(CompanionTheme.accent)
                    }
                }
                ProgressView(value: controller.round?.remaining ?? 60, total: 60)
                    .accessibilityLabel("剩余 \(Int(ceil(controller.round?.remaining ?? 60))) 秒")
                gameStage
                controls
                if isWorking {
                    Label("小可正在陪你工作，小游戏先安静歇一会儿。", systemImage: "moon.zzz")
                        .font(.callout).foregroundStyle(CompanionTheme.secondary)
                } else if let notice = controller.notice {
                    Text(notice).font(.callout).foregroundStyle(CompanionTheme.secondary)
                } else if controller.phase == .paused {
                    Text(controller.pauseReason + "，准备好后点击继续。")
                        .font(.callout).foregroundStyle(CompanionTheme.secondary)
                } else if controller.phase == .finished {
                    Text(controller.resultSaved ? "这一分钟收获了 \(controller.round?.score ?? 0) 分，成绩已经收好啦。" : "这一局完成啦，成绩未计入记录，可以重新挑战。")
                        .font(.callout).foregroundStyle(CompanionTheme.accent)
                } else {
                    Text("每局一分钟。暂停和离开游乐角时不计时，工作开始也会自动暂停。")
                        .font(.caption).foregroundStyle(CompanionTheme.secondary)
                }
            }.padding(20).background(Color.white, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(CompanionTheme.border.opacity(0.7)))
            HStack(spacing: 9) {
                Image(systemName: "gift.fill").foregroundStyle(CompanionTheme.accent)
                Text(store.gameRewardAvailable(controller.selectedKind) ? "今天第一次玩完这一项，还会收获一点成长。" : "今天的成长奖励已领到，仍然可以挑战自己的最高分。")
                    .font(.caption).foregroundStyle(CompanionTheme.secondary)
            }.padding(.horizontal, 5)
        }
        .onReceive(timer) { now in
            if isWorking { controller.pause(reason: "小可在工作", store: store, at: now) }
            else { controller.advance(store: store, at: now) }
        }
        .onChange(of: isWorking) { working in
            if working { controller.pause(reason: "小可在工作", store: store) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            controller.pause(reason: "游乐角暂时暂停了", store: store)
        }
        .onDisappear { controller.pause(reason: "离开游乐角时已暂停", store: store) }
    }

    private var instructions: String {
        switch controller.selectedKind {
        case .stars: return "拖动小篮子，或用左右按钮接住落下的星星。每颗 3 分。"
        case .hands: return "记住星星在哪只手里，双手合拢后再选。猜中得 2 分。"
        case .cookie: return "先看清饼干的位置，盖住后点它藏着的格子。找对得 3 分。"
        }
    }
    private var timeText: String {
        let remaining = Int(ceil(controller.round?.remaining ?? 60))
        return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 10) {
            switch controller.phase {
            case .ready, .finished:
                Button(controller.phase == .finished ? "再玩一分钟" : "开始一分钟") { controller.start(store: store) }
                    .buttonStyle(HUDButtonStyle(prominent: true)).disabled(isWorking)
            case .playing:
                Button("暂停一下") { controller.pause(reason: "已经暂停", store: store) }
                Button("结束这局") { controller.finishEarly(store: store) }
            case .paused:
                Button("继续游戏") { controller.resume(store: store) }
                    .buttonStyle(HUDButtonStyle(prominent: true)).disabled(isWorking)
                Button("结束这局") { controller.finishEarly(store: store) }
            }
            Spacer()
            if let round = controller.round, controller.isSessionOpen {
                Text("第 \(round.roundNumber) 轮 · \(round.misses) 次错过")
                    .font(.caption).foregroundStyle(CompanionTheme.secondary)
            }
        }
    }

    private var gameStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(CompanionTheme.sidebar.opacity(0.55))
            if let round = controller.round {
                VStack(spacing: 8) {
                    if round.kind == .stars { starsStage(round) }
                    else { memoryStage(round) }
                }.padding(14)
                if controller.phase == .paused || controller.phase == .finished {
                    RoundedRectangle(cornerRadius: 18).fill(CompanionTheme.background.opacity(0.94))
                    VStack(spacing: 10) {
                        Text(controller.phase == .paused ? "☁️" : "✨").font(.system(size: 44))
                        Text(controller.phase == .paused ? "星星和饼干都替你留着" : "小小挑战，完成啦")
                            .font(.headline)
                        Text(controller.phase == .paused ? "休息多久都没关系" : "\(round.score) 分 · 最高 \(store.gameBestScore(round.kind)) 分")
                            .font(.callout).foregroundStyle(CompanionTheme.secondary)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Text(controller.selectedKind.emoji).font(.system(size: 64))
                    Text("和小可玩一小会儿").font(.headline)
                    Text("准备好后，再开始这一分钟").font(.callout).foregroundStyle(CompanionTheme.secondary)
                }
            }
        }.frame(height: 286)
    }

    private func starsStage(_ round: PetGameRound) -> some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                ZStack {
                    ForEach(0..<7, id: \.self) { index in
                        Circle().fill(CompanionTheme.accent.opacity(0.12)).frame(width: 4, height: 4)
                            .position(x: width * CGFloat(index + 1) / 8, y: CGFloat((index * 43) % 143 + 15))
                    }
                    Text("⭐️").font(.system(size: 31))
                        .position(x: 20 + (width - 40) * round.starX, y: 15 + (height - 51) * round.starProgress)
                        .accessibilityHidden(true)
                    Text("🧺").font(.system(size: 45))
                        .position(x: 20 + (width - 40) * round.basketX, y: height - 24)
                        .accessibilityLabel("接星星的小篮子")
                    if round.roundElapsed < 0.6, let caught = round.outcome {
                        Text(caught ? "+3 ✨" : "差一点点").font(.caption.weight(.semibold))
                            .foregroundStyle(CompanionTheme.accent).position(x: width / 2, y: 17)
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    controller.moveBasket(to: Double((value.location.x - 20) / max(1, width - 40)))
                })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("星星位于\(round.starX < 0.4 ? "左边" : (round.starX > 0.6 ? "右边" : "中间"))，左右调整篮子接住")
                .accessibilityAdjustableAction { direction in
                    controller.moveBasket(to: round.basketX + (direction == .increment ? 0.16 : -0.16))
                }
            }
            HStack(spacing: 12) {
                Button { controller.moveBasket(to: round.basketX - 0.16) } label: { Label("往左", systemImage: "arrow.left") }
                    .accessibilityLabel("篮子向左")
                Button { controller.moveBasket(to: round.basketX + 0.16) } label: { Label("往右", systemImage: "arrow.right") }
                    .accessibilityLabel("篮子向右")
            }.disabled(controller.phase != .playing)
        }
    }

    private func memoryStage(_ round: PetGameRound) -> some View {
        VStack(spacing: 10) {
            Text(round.outcome != nil ? (round.outcome == true ? "找到了，真有默契！" : "下次再一起找找") : (round.isPreviewing ? "先记住它的位置…" : (round.kind == .hands ? "星星在哪只手？" : "饼干藏在哪里？")))
                .font(.callout.weight(.semibold)).foregroundStyle(CompanionTheme.accent)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: round.kind == .hands ? 2 : 3), spacing: 10) {
                ForEach(0..<round.tileCount, id: \.self) { index in
                    Button { controller.choose(index) } label: {
                        VStack(spacing: 3) {
                            Text(tileSymbol(round, index: index)).font(.system(size: round.kind == .hands ? 48 : 28))
                            if round.kind == .hands { Text(index == 0 ? "左手" : "右手").font(.caption) }
                        }.frame(maxWidth: .infinity, minHeight: round.kind == .hands ? 142 : 54)
                            .background(tileColor(round, index: index), in: RoundedRectangle(cornerRadius: 15))
                            .overlay(RoundedRectangle(cornerRadius: 15).stroke(CompanionTheme.border.opacity(0.8)))
                    }.buttonStyle(UndimmedGameButtonStyle()).disabled(!round.canChoose || controller.phase != .playing)
                        .accessibilityLabel(tileAccessibility(round, index: index))
                }
            }
        }.padding(.horizontal, round.kind == .hands ? 18 : 26)
    }

    private func tileSymbol(_ round: PetGameRound, index: Int) -> String {
        if round.isPreviewing || round.outcome != nil {
            if index == round.targetIndex { return round.kind == .hands ? "🌟" : "🍪" }
            return round.kind == .hands ? "🖐️" : ["🍓", "🍊", "🍒", "🍎", "🥨", "🍬", "🫐", "🥝", "🍋"][index]
        }
        return round.kind == .hands ? "✊" : "🐾"
    }
    private func tileColor(_ round: PetGameRound, index: Int) -> Color {
        if round.outcome != nil && index == round.targetIndex { return CompanionTheme.mint }
        if round.selectedIndex == index && round.outcome == false { return CompanionTheme.peach }
        return Color.white.opacity(0.9)
    }
    private func tileAccessibility(_ round: PetGameRound, index: Int) -> String {
        let location = round.kind == .hands ? (index == 0 ? "左手" : "右手") : "第\(index + 1)格"
        if round.isPreviewing || round.outcome != nil {
            return location + (index == round.targetIndex ? (round.kind == .hands ? "，星星在这里" : "，饼干在这里") : "，空的")
        }
        return location + "，点击选择"
    }
}

/// Targets remain legible during the memorisation phase, even though guesses are disabled.
private struct UndimmedGameButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.975 : 1)
    }
}
