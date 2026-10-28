import AppKit
import SwiftUI

@MainActor
struct PetMoodCard: View {
    @ObservedObject var store: CompanionStore
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(store.petMood.emoji).font(.system(size: 38)).padding(12)
                .background(CompanionTheme.peach.opacity(0.65), in: RoundedRectangle(cornerRadius: 20))
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("小心情 · \(store.petMood.title)").font(.headline)
                    Spacer()
                    Text("偏爱 \(store.favoriteFood.emoji) \(store.favoriteFood.title)")
                        .font(.caption).foregroundStyle(CompanionTheme.accent)
                }
                Text(store.moodDescription).font(.callout).foregroundStyle(CompanionTheme.secondary)
                Text("“\(store.contextualWish)”").font(.callout).foregroundStyle(CompanionTheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.lifeCard()
    }
}

@MainActor
struct PetHomePage: View {
    @ObservedObject var store: CompanionStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("给小可安一个家", systemImage: "house.fill").font(.headline)
                    Spacer()
                    Text("摆设会留在桌面陪着它").font(.caption).foregroundStyle(CompanionTheme.secondary)
                }
                PetRoomPreview(store: store)
                Text("工作时伏案写字，休息时靠着坐垫打盹。每件摆设都能单独放上或收起。")
                    .font(.callout).foregroundStyle(CompanionTheme.secondary)
            }.lifeCard()
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(PetHomeItem.allCases) { item in
                    let selected = store.state.life.homeItems.contains(item)
                    Button { store.setHomeItem(item, enabled: !selected) } label: {
                        HStack(spacing: 12) {
                            Group {
                                if let image = PetHomeArtwork.images[item.rawValue] {
                                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                                }
                            }.frame(width: 52, height: 46)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.title).font(.headline)
                                Text(detail(item)).font(.caption).foregroundStyle(CompanionTheme.secondary)
                            }
                            Spacer()
                            Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                                .font(.system(size: 20)).foregroundStyle(CompanionTheme.accent)
                        }.padding(16).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                            .background(selected ? CompanionTheme.lavender.opacity(0.6) : Color.white,
                                        in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18)
                                .stroke(selected ? CompanionTheme.accent.opacity(0.5) : CompanionTheme.border))
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(item.title)，\(selected ? "已摆放，点击收起" : "点击摆放")")
                }
            }
        }
    }
    private func detail(_ item: PetHomeItem) -> String {
        switch item {
        case .cushion: return "软绵绵的休息角落"
        case .desk: return "摊开书，写下小小想法"
        case .lamp: return "留一盏暖暖的灯"
        case .blanket: return "给小窝添一点暖意"
        }
    }
}

@MainActor
private struct PetRoomPreview: View {
    @ObservedObject var store: CompanionStore
    var body: some View {
        HStack(spacing: 14) {
            scene("running", title: "读书时光")
            scene("sleeping", title: "安心小憩")
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("小窝预览，已摆放：\(PetHomeItem.allCases.filter { store.state.life.homeItems.contains($0) }.map(\.title).joined(separator: "、"))")
    }
    private func scene(_ pose: String, title: String) -> some View {
        VStack(spacing: 8) {
            FittedOutfitPreview(store: store, pose: pose, showHome: true)
                .frame(height: 210).allowsHitTesting(false).accessibilityHidden(true)
            Text(title).font(.caption).foregroundStyle(CompanionTheme.secondary)
        }.padding(.bottom, 12).frame(maxWidth: .infinity)
            .background(CompanionTheme.sidebar.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
    }

}

@MainActor
struct PetWardrobePage: View {
    @ObservedObject var store: CompanionStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("今天穿得可可爱爱", systemImage: "tshirt.fill").font(.headline)
                    Spacer()
                    Button("季节搭配") { store.applySeasonalOutfit() }
                }
                HStack(spacing: 12) {
                    outfitPreview("idle", title: "日常")
                    outfitPreview("running", title: "读书")
                    outfitPreview("sleeping", title: "打盹")
                }.padding(.vertical, 4)
                Text("配饰可以自由叠搭。睡帽和盖毯会让打盹的时光更舒服。")
                    .font(.callout).foregroundStyle(CompanionTheme.secondary)
                HStack(spacing: 10) {
                    ForEach(PetSeason.allCases) { season in
                        let selected = store.state.life.season == season
                        Button { store.setSeason(season) } label: {
                            VStack(spacing: 8) {
                                Circle().fill(seasonColor(season)).frame(width: 25, height: 25)
                                    .overlay(Circle().stroke(selected ? CompanionTheme.accent : Color.clear, lineWidth: 2).padding(-4))
                                Text(season.title).font(.callout)
                            }.frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(selected ? CompanionTheme.sidebar : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain).accessibilityLabel("\(season.title)配色，\(selected ? "已选择" : "未选择")")
                    }
                }
            }.lifeCard()
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(PetAccessory.allCases) { accessory in
                    let selected = store.state.life.accessories.contains(accessory)
                    Button { store.setAccessory(accessory, enabled: !selected) } label: {
                        VStack(spacing: 10) {
                            Text(accessory.emoji).font(.system(size: 42)).frame(height: 58)
                            HStack(spacing: 7) {
                                Text(accessory.title).font(.headline)
                                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(CompanionTheme.accent) }
                            }
                            Text(selected ? "已穿戴 · 点击取下" : "点击给小可戴上")
                                .font(.caption).foregroundStyle(CompanionTheme.secondary)
                        }.frame(maxWidth: .infinity).padding(20)
                            .background(selected ? seasonColor(store.state.life.season).opacity(0.32) : Color.white,
                                        in: RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20)
                                .stroke(selected ? CompanionTheme.accent.opacity(0.5) : CompanionTheme.border))
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(accessory.title)，\(selected ? "已穿戴，点击取下" : "点击穿戴")")
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "heart.fill").foregroundStyle(CompanionTheme.accent)
                Text(store.state.life.accessories.isEmpty ? "轻轻松松，也很好看。" : "已搭配：" + PetAccessory.allCases.filter { store.state.life.accessories.contains($0) }.map(\.title).joined(separator: "、"))
                    .font(.callout).foregroundStyle(CompanionTheme.secondary)
            }.lifeCard()
        }
    }
    private func outfitPreview(_ pose: String, title: String) -> some View {
        VStack(spacing: 4) {
            FittedOutfitPreview(store: store, pose: pose).frame(height: 180)
                .allowsHitTesting(false).accessibilityHidden(true)
            Text(title).font(.caption).foregroundStyle(CompanionTheme.secondary)
        }.frame(maxWidth: .infinity)
            .background(CompanionTheme.sidebar.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
    }

    private func seasonColor(_ season: PetSeason) -> Color {
        switch season {
        case .spring: return Color(red: 0.96, green: 0.75, blue: 0.82)
        case .summer: return Color(red: 0.64, green: 0.86, blue: 0.79)
        case .autumn: return Color(red: 0.95, green: 0.74, blue: 0.49)
        case .winter: return Color(red: 0.73, green: 0.78, blue: 0.96)
        }
    }
}

private struct LifeCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(CompanionTheme.border.opacity(0.6)))
            .shadow(color: CompanionTheme.accent.opacity(0.035), radius: 9, y: 4)
    }
}

extension View {
    fileprivate func lifeCard() -> some View { modifier(LifeCardModifier()) }
}

@MainActor
private struct FittedOutfitPreview: NSViewRepresentable {
    @ObservedObject var store: CompanionStore
    let pose: String
    var showHome = false
    func makeNSView(context: Context) -> NSView {
        guard let atlas = try? store.state.settings.appearance.loadAtlas() else { return NSView() }
        let canvas = SpriteCanvas(atlas: atlas)
        canvas.scale = showHome ? 0.9 : 0.74
        canvas.mouseFollow = false
        canvas.quiet = true
        canvas.setAccessibilityElement(false)
        return canvas
    }
    func updateNSView(_ view: NSView, context: Context) {
        guard let canvas = view as? SpriteCanvas else { return }
        canvas.outfitItems = Set(store.state.life.accessories.map(\.rawValue))
        canvas.homeItems = showHome ? Set(store.state.life.homeItems.map(\.rawValue)) : []
        canvas.focused = pose == "running"
        canvas.season = store.state.life.season.rawValue
        if canvas.animationName != pose { canvas.play(pose, duration: 3600) }
    }
}
