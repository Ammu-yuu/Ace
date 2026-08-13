import AppKit

// MARK: - Sprite config (assets/ace.json)

/// One animation clip: an ordered list of frame image files played at `fps`.
/// Filenames are relative to the sprites directory (see `SpriteConfig`).
struct SpriteAnimation: Codable {
    var frames: [String]
    var fps: Double
}

/// Top-level shape of `assets/ace.json`. This is the classic Shimeji layout:
/// individual PNG frames (e.g. `shime1.png`), grouped into named clips.
struct SpriteConfig: Codable {
    /// Folder holding the frame PNGs, relative to `assets/`. Defaults to `sprites`.
    var spritesDir: String?
    var animations: [String: SpriteAnimation]
}

/// Loads individual sprite frames from `assets/<spritesDir>/` as described by
/// `assets/ace.json`, grouped by pet state. If the config or images are missing,
/// `hasRealSprites` is false and the UI shows the code-drawn placeholder — so the
/// app runs with or without art (and a fresh git clone, which ships no art, still
/// works).
final class SpriteLibrary {

    private(set) var frames: [PetState: [NSImage]] = [:]
    private(set) var fps: [PetState: Double] = [:]

    var hasRealSprites: Bool { !frames.isEmpty }

    init() {
        load()
    }

    /// A one-line report of what loaded, for the startup diagnostic.
    func summary() -> String {
        guard hasRealSprites else { return "no sprites" }
        let parts = PetState.allCases.compactMap { state -> String? in
            guard let n = frames[state]?.count else { return nil }
            return "\(state.rawValue):\(n)"
        }
        return parts.joined(separator: " ")
    }

    /// Where to look for `assets/`, in priority order:
    /// 1. Inside a built .app bundle (`Contents/Resources/assets`)
    /// 2. The current working directory (typical for `swift run`)
    /// 3. The package root, derived from this source file's path
    private func assetsDirectory() -> URL? {
        var candidates: [URL] = []

        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent("assets"))
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates.append(cwd.appendingPathComponent("assets"))

        // .../Sources/AcePet/App/SpriteLibrary.swift → up 4 → package root
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // App
            .deletingLastPathComponent()   // AcePet
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // <root>
        candidates.append(packageRoot.appendingPathComponent("assets"))

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func load() {
        guard let dir = assetsDirectory() else { return }

        let jsonURL = dir.appendingPathComponent("ace.json")
        guard
            FileManager.default.fileExists(atPath: jsonURL.path),
            let data = try? Data(contentsOf: jsonURL),
            let config = try? JSONDecoder().decode(SpriteConfig.self, from: data)
        else {
            return   // no (valid) config → placeholder mode
        }

        let spritesDir = dir.appendingPathComponent(config.spritesDir ?? "sprites")

        for (name, anim) in config.animations {
            guard let state = PetState(rawValue: name) else { continue }

            let images = anim.frames.compactMap { file -> NSImage? in
                NSImage(contentsOf: spritesDir.appendingPathComponent(file))
            }

            if !images.isEmpty {
                frames[state] = images
                fps[state] = anim.fps
            }
        }
    }
}
