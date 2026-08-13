import Foundation
import SwiftUI

/// Drives the talk loop and the UI state around it:
/// mic → speech-to-text → brain → speech bubble, flipping the pet's animation
/// state (idle → listening → thinking → speaking) along the way.
@MainActor
final class PetViewModel: ObservableObject {

    @Published var userText: String = ""
    @Published var replyText: String = "Hi, I'm Ace. Tap the mic and talk to me."
    @Published var statusLine: String = ""
    @Published var isListening: Bool = false

    private let stt: SpeechToText
    private let brain: BrainAdapter
    private let animator: PetAnimator

    /// Short rolling conversation history (fuller version in Step F).
    private var history: [BrainMessage] = []
    private let historyLimit = 10

    private var idleResetTask: Task<Void, Never>?

    init(stt: SpeechToText, brain: BrainAdapter, animator: PetAnimator) {
        self.stt = stt
        self.brain = brain
        self.animator = animator
    }

    /// Push-to-talk toggle: first tap starts listening, second tap sends.
    func micTapped() {
        if isListening {
            Task { await finishListening() }
        } else {
            Task { await startListening() }
        }
    }

    private func startListening() async {
        idleResetTask?.cancel()

        guard await stt.requestAuthorization() else {
            replyText = "I need microphone + speech access. Enable them in System Settings ▸ Privacy & Security."
            return
        }

        do {
            try stt.start { [weak self] partial in
                Task { @MainActor in self?.userText = partial }
            }
            isListening = true
            userText = ""
            statusLine = "Listening…"
            animator.state = .listening
        } catch {
            replyText = "Couldn't start the mic: \(error.localizedDescription)"
            animator.state = .idle
        }
    }

    private func finishListening() async {
        let text = await stt.stop()
        isListening = false
        statusLine = ""

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        userText = trimmed

        guard !trimmed.isEmpty else {
            replyText = "I didn't catch that — try again?"
            animator.state = .idle
            return
        }

        // Think.
        animator.state = .thinking
        statusLine = "Thinking…"
        append(.init(role: .user, text: trimmed))

        do {
            let reply = try await brain.reply(to: trimmed, history: history)
            append(.init(role: .assistant, text: reply))
            replyText = reply
            statusLine = ""

            // Speak (visually for now; audio TTS arrives in Step E).
            animator.state = .speaking
            scheduleIdleReset(after: 2.5)
        } catch {
            replyText = "Brain error: \(error.localizedDescription)"
            statusLine = ""
            animator.state = .idle
        }
    }

    private func append(_ message: BrainMessage) {
        history.append(message)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
    }

    private func scheduleIdleReset(after seconds: Double) {
        idleResetTask?.cancel()
        idleResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            if !self.isListening { self.animator.state = .idle }
        }
    }
}
