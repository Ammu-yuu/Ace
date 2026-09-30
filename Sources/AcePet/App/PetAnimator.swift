import AppKit
import SwiftUI

/// Drives frame-by-frame animation for the current `PetState`.
///
/// When real sprites are loaded it runs a timer that advances the frame index at
/// the clip's fps. When no sprites are present, `currentImage` stays `nil` and
/// the view falls back to the animated placeholder — so no timer is needed.
@MainActor
final class PetAnimator: ObservableObject {

    @Published private(set) var currentImage: NSImage?

    /// Change this to switch clips (idle → listening → thinking → speaking).
    @Published var state: PetState = .idle {
        didSet {
            if oldValue != state { startClip() }
        }
    }

    /// Horizontal mirror, set by the roaming engine so Ace faces the way he
    /// walks. The base sprites face left, so we mirror when he moves right.
    @Published var flipped: Bool = false

    var hasRealSprites: Bool { library.hasRealSprites }

    private let library: SpriteLibrary
    private var timer: Timer?
    private var frameIndex = 0

    init(library: SpriteLibrary = SpriteLibrary()) {
        self.library = library
        startClip()
    }

    /// (Re)start animating the clip for the current state, falling back to the
    /// idle clip if a given state has no frames.
    private func startClip() {
        timer?.invalidate()
        timer = nil
        frameIndex = 0

        let clip = library.frames[state] ?? library.frames[.idle]
        let clipFps = library.fps[state] ?? library.fps[.idle] ?? 6

        guard let frames = clip, !frames.isEmpty else {
            currentImage = nil   // placeholder mode
            return
        }

        currentImage = frames[0]
        guard frames.count > 1 else { return }   // single-frame clip: nothing to animate

        let interval = 1.0 / max(clipFps, 1)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advance(frames) }
        }
    }

    private func advance(_ frames: [NSImage]) {
        frameIndex = (frameIndex + 1) % frames.count
        currentImage = frames[frameIndex]
    }
}
