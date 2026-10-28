import AppKit

@MainActor
extension PetAppearance {
    var resourceName: String { self == .whiteDragon ? "spritesheet" : "l3d-spritesheet" }
    var atlasURL: URL {
        Bundle.main.url(forResource: resourceName, withExtension: "png")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/\(resourceName).png")
    }
    func loadAtlas() throws -> SpriteAtlas {
        if let cached = AppearanceAtlases.images[self] { return cached }
        let atlas = try SpriteAtlas(url: atlasURL)
        AppearanceAtlases.images[self] = atlas
        return atlas
    }
    var previewImage: NSImage? { try? loadAtlas().frames[0][0] }
}

/// Immutable artwork is shared by the desktop, sidebar, room and wardrobe.
/// Opening a page never reconstructs all animation frames for each preview.
@MainActor private enum AppearanceAtlases {
    static var images: [PetAppearance: SpriteAtlas] = [:]
}
