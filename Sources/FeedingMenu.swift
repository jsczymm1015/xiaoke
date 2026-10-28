import AppKit

/// Both the desktop context menu and menu-bar item use the same feeding actions.
@MainActor final class FeedingMenuController: NSObject, NSMenuDelegate {
    private let store: CompanionStore
    private let openKitchen: () -> Void

    init(store: CompanionStore, openKitchen: @escaping () -> Void) {
        self.store = store
        self.openKitchen = openKitchen
    }

    func makeMenuItem() -> NSMenuItem {
        let root = NSMenuItem(title: "喂养小食堂", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: root.title)
        menu.autoenablesItems = false
        let open = NSMenuItem(title: "打开小食堂…", action: #selector(showKitchen), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        for category in PetFoodCategory.allCases {
            let group = NSMenuItem(title: category.title, action: nil, keyEquivalent: "")
            let choices = NSMenu(title: category.title)
            choices.autoenablesItems = false
            choices.delegate = self
            for food in PetFood.allCases where food.category == category {
                let choice = NSMenuItem(title: food.title, action: #selector(serve(_:)), keyEquivalent: "")
                choice.target = self
                choice.representedObject = food.rawValue
                choices.addItem(choice)
            }
            menuNeedsUpdate(choices)
            group.submenu = choices
            menu.addItem(group)
        }
        root.submenu = menu
        return root
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            guard let raw = item.representedObject as? String, let food = PetFood(rawValue: raw) else { continue }
            let reason = store.feedingBlockReason(food)
            let remaining = Int(ceil(store.feedingCooldownRemaining(food)))
            let suffix = remaining > 0 ? String(format: "（%d:%02d）", remaining / 60, remaining % 60)
                : (reason == nil ? "" : "（吃饱啦）")
            item.title = "\(food.emoji) \(food.title)\(suffix)"
            item.isEnabled = reason == nil
            item.toolTip = ([food.detail, food.effectDescription] + [reason].compactMap { $0 }).joined(separator: "\n")
        }
    }

    @objc private func showKitchen() { openKitchen() }
    @objc private func serve(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let food = PetFood(rawValue: raw) else { return }
        _ = store.feed(food)
    }
}
