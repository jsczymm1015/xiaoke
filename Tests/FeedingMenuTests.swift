import AppKit
import Foundation

@main struct FeedingMenuTests {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            assertions += 1
            guard condition() else {
                throw NSError(domain: "FeedingMenuTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xiaoke-feeding-menu-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = CompanionStore(directory: directory, now: { now })
        var settings = store.state.settings
        settings.interactionFrequency = 0
        settings.restReminderMinutes = 0
        store.updateSettings(settings)
        while store.toast != nil { store.dismissToast() }
        var kitchenOpened = 0
        let controller = FeedingMenuController(store: store) { kitchenOpened += 1 }
        let root = controller.makeMenuItem().submenu!
        let groups = root.items.compactMap(\.submenu)
        try expect(groups.count == 3, "Feeding menu must expose all three food categories")
        let items = groups.flatMap(\.items)
        let identifiers = items.compactMap { $0.representedObject as? String }
        try expect(Set(identifiers) == Set(PetFood.allCases.map(\.rawValue)), "Menu must contain each of the eight choices exactly once")
        try expect(items.count == 8, "Menu must not duplicate choices")
        try expect(items.allSatisfy { $0.isEnabled && !($0.toolTip ?? "").isEmpty }, "Available food must expose effect descriptions")
        root.performActionForItem(at: 0)
        try expect(kitchenOpened == 1 && store.feedingHistory.isEmpty, "Open kitchen must navigate without feeding")

        func choice(_ food: PetFood) -> (NSMenu, Int) {
            let menu = groups.first { $0.items.contains { $0.representedObject as? String == food.rawValue } }!
            return (menu, menu.items.firstIndex { $0.representedObject as? String == food.rawValue }!)
        }
        let rice = choice(.riceBall)
        rice.0.performActionForItem(at: rice.1)
        try expect(store.feedingHistory.count == 1 && store.state.stats.hunger == 0, "Selecting rice must execute feeding through the menu target")
        let xp = store.state.stats.experience
        let staleApple = choice(.apple)
        staleApple.0.performActionForItem(at: staleApple.1)
        try expect(store.state.stats.experience == xp && store.feedingHistory.count == 1, "An already-open stale menu must not bypass the shared food cooldown")
        for group in groups { controller.menuNeedsUpdate(group) }
        try expect(items.filter { !PetFood(rawValue: $0.representedObject as! String)!.isLightDrink }.allSatisfy { !$0.isEnabled }, "Food and milk must share disabled cooldown state")
        try expect(rice.0.items[rice.1].title.contains("5:00"), "Reopening the menu must show current cooldown time")
        let water = choice(.water)
        try expect(water.0.items[water.1].isEnabled, "Water remains available after eating")
        water.0.performActionForItem(at: water.1)
        controller.menuNeedsUpdate(water.0)
        let tea = choice(.herbalTea)
        try expect(!tea.0.items[tea.1].isEnabled && store.feedingHistory.count == 2, "Water must apply the shared drink cooldown to tea")
        now += 121
        store.tick()
        controller.menuNeedsUpdate(water.0)
        try expect(tea.0.items[tea.1].isEnabled, "Menu reopening must reenable drinks after their cooldown")
        now += 181
        store.tick()
        controller.menuNeedsUpdate(rice.0)
        try expect(!rice.0.items[rice.1].isEnabled && rice.0.items[rice.1].title.contains("吃饱"), "Food stays unavailable while full after cooldown expires")
        now += 3 * 3600
        store.tick()
        controller.menuNeedsUpdate(rice.0)
        try expect(rice.0.items[rice.1].isEnabled, "The menu must recover when appetite returns")
        print("PASS: \(assertions) native feeding menu assertions — categories, navigation, action dispatch, stale actions, shared cooldowns, full refusal and recovery")
    }
}
