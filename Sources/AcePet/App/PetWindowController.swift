import AppKit
import SwiftUI

/// Creates the always-on-top, transparent window that hosts the pet, and owns
/// the pieces that drive it: the sprite animator, the talk loop (view model),
/// and the roaming engine. The window is tall enough to fit a speech bubble
/// above the bottom-anchored character.
@MainActor
final class PetWindowController {

    let window: PetWindow
    let spriteLibrary = SpriteLibrary()
    lazy var animator = PetAnimator(library: spriteLibrary)
    lazy var viewModel = PetViewModel(
        stt: AppleSpeechToText(),
        brain: StubBrain(),          // mock brain — swapped for Ollama in Step D
        animator: animator
    )
    private lazy var roam = RoamController(window: window, animator: animator)

    init() {
        // Narrow window (just wide enough for the bubble); extra height above the
        // character leaves room for the bubble. The character sits at the bottom.
        let contentSize = NSSize(width: 220, height: 300)

        window = PetWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = false     // we handle dragging ourselves
        window.ignoresMouseEvents = false

        wireInteractions()

        let actions = PetActions(
            onTap:       { [weak self] in self?.viewModel.micTapped() },
            onGrabStart: { [weak self] in self?.roam.beginDrag() },
            onGrabMove:  { [weak self] t in self?.roam.dragBy(t) },
            onGrabEnd:   { [weak self] in self?.roam.endDrag() },
            onQuit:      { NSApp.terminate(nil) }
        )
        window.contentView = NSHostingView(
            rootView: PetView(animator: animator, vm: viewModel, actions: actions)
        )
    }

    /// Pause roaming while talking; resume when the turn ends.
    private func wireInteractions() {
        viewModel.onInteractionStart = { [weak self] in self?.roam.pauseForInteraction() }
        viewModel.onInteractionEnd   = { [weak self] in self?.roam.resumeRoaming() }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        roam.start()
    }
}
