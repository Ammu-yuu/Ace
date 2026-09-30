import Foundation
import SwiftUI

/// Drives the hands-free talk loop and the UI around it:
/// always-on wake word ("Ace") → command → brain → speech bubble, flipping the
/// pet's animation state (listening → thinking → speaking) along the way.
///
/// Tapping the pet captures a command immediately (skipping the wake word).
/// While a turn is in progress it pauses roaming (`onInteractionStart`) and the
/// wake engine, resuming both afterwards.
@MainActor
final class PetViewModel: ObservableObject {

    @Published var userText: String = ""
    @Published var replyText: String = "Say “Ace” to talk to me."
    @Published var statusLine: String = ""
    @Published var isListening: Bool = false
    @Published var bubbleVisible: Bool = false

    /// Set by the owner to pause/resume roaming around a conversation turn.
    var onInteractionStart: () -> Void = {}
    var onInteractionEnd: () -> Void = {}

    private let wake: WakeWordEngine
    private let brain: BrainAdapter
    private let tts: TextToSpeech
    private let animator: PetAnimator

    /// Short rolling conversation history.
    private var history: [BrainMessage] = []
    private let historyLimit = 10

    private var idleResetTask: Task<Void, Never>?
    private var ambientTask: Task<Void, Never>?

    init(wake: WakeWordEngine, brain: BrainAdapter, tts: TextToSpeech, animator: PetAnimator) {
        self.wake = wake
        self.brain = brain
        self.tts = tts
        self.animator = animator
    }

    /// Begin always-on, on-device wake-word listening. Call once after the
    /// window is shown.
    func beginHandsFree() {
        wake.onWake = { [weak self] in self?.handleWake() }
        wake.onPartialCommand = { [weak self] partial in self?.userText = partial }
        wake.onCommand = { [weak self] text in Task { await self?.process(text) } }
        wake.onUnavailable = { [weak self] message in self?.showNotice(message) }

        Task { [weak self] in
            guard let self else { return }
            guard await self.wake.requestAuthorization() else {
                self.showNotice("I need microphone + speech access. Enable them in System Settings ▸ Privacy & Security, then relaunch me.")
                return
            }
            self.wake.start()
            self.showNotice("Say “Ace” to talk to me.")
        }
    }

    /// Tap the pet to talk without saying the wake word.
    func micTapped() {
        guard !isListening else { return }
        wake.forceCapture()
    }

    // MARK: - Turn flow

    private func handleWake() {
        idleResetTask?.cancel()
        ambientTask?.cancel()
        onInteractionStart()               // stop roaming while we talk
        isListening = true
        userText = ""
        replyText = ""
        statusLine = "Listening…"
        bubbleVisible = true
        animator.state = .listening
    }

    private func process(_ text: String) async {
        isListening = false
        statusLine = ""

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        userText = trimmed

        guard !trimmed.isEmpty else {
            replyText = "I didn't catch that — say “Ace” and try again."
            endTurn(after: 2.0)
            return
        }

        animator.state = .thinking
        statusLine = "Thinking…"
        append(.init(role: .user, text: trimmed))

        do {
            let reply = try await brain.reply(to: trimmed, history: history)
            append(.init(role: .assistant, text: reply))
            replyText = reply
            statusLine = ""
            animator.state = .speaking

            // Speak it; end the turn when audio finishes (with a safety timeout).
            endTurn(after: 20)
            tts.speak(reply) { [weak self] in
                Task { @MainActor in self?.endTurn(after: 0.4) }
            }
        } catch {
            replyText = (error as? BrainError)?.errorDescription
                ?? "Something went wrong: \(error.localizedDescription)"
            statusLine = ""
            endTurn(after: 4.0)
        }
    }

    /// A brief in-character line from the roaming engine (e.g. "*yawn*").
    func speakAmbient(_ line: String) {
        guard !isListening, !bubbleVisible else { return }
        ambientTask?.cancel()
        userText = ""
        statusLine = ""
        replyText = line
        bubbleVisible = true
        ambientTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, !Task.isCancelled, !self.isListening else { return }
            self.bubbleVisible = false
        }
    }

    // MARK: - Helpers

    private func append(_ message: BrainMessage) {
        history.append(message)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
    }

    /// Hide the bubble, resume roaming, and resume wake-word listening.
    private func endTurn(after seconds: Double) {
        idleResetTask?.cancel()
        idleResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled, !self.isListening else { return }
            self.bubbleVisible = false
            self.onInteractionEnd()
            self.wake.resumeListening()
        }
    }

    /// Show a transient informational bubble (no turn, doesn't touch roaming or
    /// restart listening).
    private func showNotice(_ text: String) {
        guard !isListening else { return }
        replyText = text
        statusLine = ""
        userText = ""
        bubbleVisible = true
        ambientTask?.cancel()
        ambientTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard let self, !Task.isCancelled, !self.isListening else { return }
            self.bubbleVisible = false
        }
    }
}
