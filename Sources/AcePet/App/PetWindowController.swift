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
        wake: WakeWordEngine(),
        brain: Self.makeBrain(),
        tts: Self.makeVoice(),
        skills: SkillRouter(),
        animator: animator
    )

    /// Brain selection:
    ///  - Claude API when an `ANTHROPIC_API_KEY` is present in `.env`;
    ///  - else local Ollama if it's been explicitly configured;
    ///  - else an "unconfigured" brain that tells the user to add a key.
    private static func makeBrain() -> BrainAdapter {
        if let key = Config.value("ANTHROPIC_API_KEY") {
            let model = Config.value("ANTHROPIC_MODEL") ?? "claude-haiku-4-5"
            return AnthropicBrain(apiKey: key, model: model)
        }
        if let host = Config.value("OLLAMA_HOST") ?? Config.value("OLLAMA_MODEL").map({ _ in "http://localhost:11434" }) {
            let model = Config.value("OLLAMA_MODEL") ?? "llama3.2"
            return OllamaBrain(host: host, model: model)
        }
        return UnconfiguredBrain()
    }

    /// ElevenLabs voice if an API key is present, otherwise the system voice.
    private static func makeVoice() -> TextToSpeech {
        let system = AppleTTS()
        guard let apiKey = Config.value("ELEVENLABS_API_KEY") else { return system }
        let voiceID = Config.value("ELEVENLABS_VOICE_ID") ?? "tEo3d4j7gzVojBL5Z4Pt"
        return ElevenLabsTTS(apiKey: apiKey, voiceID: voiceID, fallback: system)
    }
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
        roam.onAmbient = { [weak self] line in self?.viewModel.speakAmbient(line) }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        roam.start()
        viewModel.startVoice()          // tap-to-talk (mic off until tapped)
    }
}
