import Foundation
import SwiftUI

/// Drives the talk loop and the UI state around it:
/// mic → speech-to-text → brain → speech bubble, flipping the pet's animation
/// state (listening → thinking → speaking) along the way.
///
/// While a turn is in progress it asks the roaming engine to hold still (via
/// `onInteractionStart`) and to resume afterwards (`onInteractionEnd`), so Ace
/// stops walking to talk with you.
@MainActor
final class PetViewModel: ObservableObject {

    @Published var userText: String = ""
    @Published var replyText: String = "Hi, I'm Ace."
    @Published var statusLine: String = ""
    @Published var isListening: Bool = false
    @Published var bubbleVisible: Bool = false

    /// Set by the owner to pause/resume roaming around a conversation turn.
    var onInteractionStart: () -> Void = {}
    var onInteractionEnd: () -> Void = {}

    private let stt: SpeechToText
    private let brain: BrainAdapter
    private let animator: PetAnimator

    /// Short rolling conversation history (fuller version in Step F).
    private var history: [BrainMessage] = []
    private let historyLimit = 10

    private var idleResetTask: Task<Void, Never>?
    private var ambientTask: Task<Void, Never>?

    // End-of-speech (silence) detection.
    private var silenceMonitor: Task<Void, Never>?
    private var lastSpeechAt = Date()
    private var heardSpeech = false
    private var isFinishing = false
    private let silenceTimeout: TimeInterval = 1.5   // quiet this long → auto-send
    private let maxListen: TimeInterval = 20          // safety cap

    init(stt: SpeechToText, brain: BrainAdapter, animator: PetAnimator) {
        self.stt = stt
        self.brain = brain
        self.animator = animator
    }

    /// A brief in-character line from the roaming engine (e.g. "*yawn*"). Shows
    /// a short bubble without pausing roaming, and never overrides an active turn.
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

    /// Tap-to-talk toggle: first tap starts listening, second tap sends.
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
            showBubble("I need microphone + speech access. Enable them in System Settings ▸ Privacy & Security.")
            return
        }

        onInteractionStart()               // stop roaming while we talk

        heardSpeech = false
        isFinishing = false
        lastSpeechAt = Date()

        do {
            try stt.start { [weak self] partial in
                Task { @MainActor in
                    guard let self else { return }
                    self.userText = partial
                    if !partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.heardSpeech = true
                        self.lastSpeechAt = Date()      // reset the silence clock
                    }
                }
            }
            isListening = true
            userText = ""
            statusLine = "Listening…"
            bubbleVisible = true
            animator.state = .listening
            startSilenceMonitor()
        } catch {
            showBubble("Couldn't start the mic: \(error.localizedDescription)")
            endInteraction()
        }
    }

    /// Watches for the user to finish speaking: once they've said something and
    /// then gone quiet for `silenceTimeout`, auto-send. Also caps a runaway
    /// session at `maxListen`.
    private func startSilenceMonitor() {
        let startedAt = Date()
        silenceMonitor?.cancel()
        silenceMonitor = Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self, !Task.isCancelled, self.isListening else { return }
                let now = Date()
                let wentQuiet = self.heardSpeech && now.timeIntervalSince(self.lastSpeechAt) > self.silenceTimeout
                let tooLong = now.timeIntervalSince(startedAt) > self.maxListen
                if wentQuiet || tooLong {
                    await self.finishListening()
                    return
                }
            }
        }
    }

    private func finishListening() async {
        guard !isFinishing else { return }     // don't double-fire (tap + auto-stop)
        isFinishing = true
        silenceMonitor?.cancel()

        let text = await stt.stop()
        isListening = false
        statusLine = ""

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        userText = trimmed

        guard !trimmed.isEmpty else {
            replyText = "I didn't catch that — try again?"
            scheduleReturnToRoaming(after: 2.0)
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
            animator.state = .speaking      // audio TTS arrives in Step E
            scheduleReturnToRoaming(after: 3.0)
        } catch {
            replyText = "Brain error: \(error.localizedDescription)"
            statusLine = ""
            scheduleReturnToRoaming(after: 2.5)
        }
    }

    private func append(_ message: BrainMessage) {
        history.append(message)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
    }

    /// Show a one-off message bubble that fades back to roaming.
    private func showBubble(_ text: String) {
        replyText = text
        statusLine = ""
        userText = ""
        bubbleVisible = true
        scheduleReturnToRoaming(after: 3.0)
    }

    private func scheduleReturnToRoaming(after seconds: Double) {
        idleResetTask?.cancel()
        idleResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled, !self.isListening else { return }
            self.endInteraction()
        }
    }

    private func endInteraction() {
        bubbleVisible = false
        onInteractionEnd()                 // hand control back to the roaming engine
    }
}
