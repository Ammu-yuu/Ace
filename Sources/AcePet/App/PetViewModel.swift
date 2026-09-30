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
    @Published var replyText: String = "Tap me to talk."
    @Published var statusLine: String = ""
    @Published var isListening: Bool = false
    @Published var bubbleVisible: Bool = false

    /// Set by the owner to pause/resume roaming around a conversation turn.
    var onInteractionStart: () -> Void = {}
    var onInteractionEnd: () -> Void = {}

    /// When true, Ace listens continuously for the wake word "Ace". When false
    /// (the default), the mic only turns on when you tap him — so the macOS mic
    /// indicator isn't lit the whole time.
    var handsFree = false

    private let wake: WakeWordEngine
    private let brain: BrainAdapter
    private let tts: TextToSpeech
    private let skills: SkillRouter
    private let animator: PetAnimator

    /// Short rolling conversation history.
    private var history: [BrainMessage] = []
    private let historyLimit = 10

    private var idleResetTask: Task<Void, Never>?
    private var ambientTask: Task<Void, Never>?

    private let bookReader: BookReader

    init(wake: WakeWordEngine, brain: BrainAdapter, tts: TextToSpeech, skills: SkillRouter, animator: PetAnimator) {
        self.wake = wake
        self.brain = brain
        self.tts = tts
        self.skills = skills
        self.animator = animator
        self.bookReader = BookReader(tts: tts)

        bookReader.onChunk = { [weak self] chunk in
            self?.replyText = String(chunk.prefix(160))
            self?.bubbleVisible = true
        }
        bookReader.onFinished = { [weak self] in self?.endReading() }
    }

    /// Wire up voice and request permission. In tap-to-talk mode (the default)
    /// the mic stays off until you tap Ace; in hands-free mode it also starts
    /// continuous wake-word listening.
    func startVoice() {
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
            if self.handsFree {
                self.wake.start()
                self.showNotice("Say “Ace” to talk to me.")
            }
            // Tap-to-talk mode: nothing running until the user taps.
        }
    }

    /// Tap the pet: stop reading if he's mid-book, otherwise start a voice turn.
    func micTapped() {
        guard !isListening else { return }
        if bookReader.isReading {
            bookReader.stop()
            endReading()
            return
        }
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
            replyText = "I didn't catch that — tap me and try again."
            endTurn(after: 2.0)
            return
        }

        append(.init(role: .user, text: trimmed))

        // 0) Read a public-domain book aloud?
        if bookReader.isReadRequest(trimmed) {
            animator.state = .thinking
            statusLine = "Finding a book…"
            let intro = await bookReader.start(trimmed)
            if bookReader.isReading {
                statusLine = ""
                replyText = intro
                bubbleVisible = true
                animator.state = .speaking      // reader drives the TTS; roaming stays paused
            } else {
                deliver(intro)                  // it was a read request, but it failed
            }
            return
        }

        animator.state = .thinking
        statusLine = "Thinking…"

        // 1) Free built-in skills first (dictionary, …) — no LLM, no cost.
        if let skillReply = await skills.handle(trimmed) {
            deliver(skillReply)
            return
        }

        // 2) Otherwise, fall back to the language-model brain.
        do {
            let reply = try await brain.reply(to: trimmed, history: history)
            deliver(reply)
        } catch {
            replyText = (error as? BrainError)?.errorDescription
                ?? "Something went wrong: \(error.localizedDescription)"
            statusLine = ""
            endTurn(after: 4.0)
        }
    }

    /// Reading finished (or was stopped): hide the bubble and hand control back
    /// to the roaming engine.
    private func endReading() {
        bubbleVisible = false
        animator.state = .idle
        onInteractionEnd()          // resume roaming (mic is already off in tap mode)
    }

    /// Show + speak a reply and wind the turn down.
    private func deliver(_ reply: String) {
        append(.init(role: .assistant, text: reply))
        replyText = reply
        statusLine = ""
        animator.state = .speaking
        endTurn(after: 20)                    // safety timeout
        tts.speak(reply) { [weak self] in
            Task { @MainActor in self?.endTurn(after: 0.4) }
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

    /// Hide the bubble, resume roaming, and either resume wake-word listening
    /// (hands-free) or fully release the mic (tap-to-talk).
    private func endTurn(after seconds: Double) {
        idleResetTask?.cancel()
        idleResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled, !self.isListening else { return }
            self.bubbleVisible = false
            self.onInteractionEnd()
            if self.handsFree {
                self.wake.resumeListening()
            } else {
                self.wake.stop()          // mic off until the next tap
            }
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
