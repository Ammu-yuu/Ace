import AppKit

// MARK: - Sprite sheet config (assets/ace.json)

/// One animation clip within the sheet: a run of `frames` cells starting at
/// (`row`, `startCol`), played at `fps`. Coordinates and sizes are in *pixels*
/// of the actual PNG.
struct SpriteAnimation: Codable {
    var row: Int
    var startCol: Int?
    var frames: Int
    var fps: Double
}

/// Top-level shape of `assets/ace.json`.
struct SpriteConfig: Codable {
    var frameWidth: Int
    var frameHeight: Int
    var animations: [String: SpriteAnimation]
}

/// Loads a sprite sheet (`assets/ace_sheet.png` + `assets/ace.json`) and slices
/// it into per-state frame arrays. If no sheet is present, `hasRealSprites` is
/// false and the UI shows the code-drawn placeholder instead — so the app runs
/// with or without art.
final class SpriteLibrary {

    private(set) var frames: [PetState: [NSImage]] = [:]
    private(set) var fps: [PetState: Double] = [:]

    var hasRealSprites: Bool { !frames.isEmpty }

    init() {
        load()
    }

    /// Where to look for `assets/`, in priority order:
    /// 1. Inside a built .app bundle (`Contents/Resources/assets`)
    /// 2. The current working directory (typical for `swift run`)
    /// 3. The package root, derived from this source file's path (works no
    ///    matter what the working directory is)
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

        let sheetURL = dir.appendingPathComponent("ace_sheet.png")
        let jsonURL = dir.appendingPathComponent("ace.json")

        guard
            FileManager.default.fileExists(atPath: sheetURL.path),
            FileManager.default.fileExists(atPath: jsonURL.path),
            let sheet = NSImage(contentsOf: sheetURL),
            let data = try? Data(contentsOf: jsonURL),
            let config = try? JSONDecoder().decode(SpriteConfig.self, from: data)
        else {
            return   // no (valid) sheet → placeholder mode
        }

        for (name, anim) in config.animations {
            guard let state = PetState(rawValue: name) else { continue }

            var images: [NSImage] = []
            let start = anim.startCol ?? 0
            for i in 0..<max(anim.frames, 0) {
                let col = start + i
                let rect = CGRect(
                    x: col * config.frameWidth,
                    y: anim.row * config.frameHeight,
                    width: config.frameWidth,
                    height: config.frameHeight
                )
                if let frame = crop(sheet, to: rect) {
                    images.append(frame)
                }
            }

            if !images.isEmpty {
                frames[state] = images
                fps[state] = anim.fps
            }
        }
    }

    /// Crop a sub-rectangle out of the sheet. Uses the underlying `CGImage`
    /// whose origin is top-left in pixel space — which matches how sprite sheets
    /// are laid out (row 0 at the top).
    private func crop(_ image: NSImage, to rect: CGRect) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let sub = cg.cropping(to: rect) else {
            return nil
        }
        return NSImage(cgImage: sub, size: NSSize(width: rect.width, height: rect.height))
    }
}
