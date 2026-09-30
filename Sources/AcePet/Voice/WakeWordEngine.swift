import Foundation
import Speech
import AVFoundation

/// Continuous, on-device hands-free listening with a wake word.
///
/// It always listens (locally — nothing leaves the Mac) but stays quiet until it
/// hears **"Ace"**. Everything spoken after the wake word, up to a short silence,
/// becomes the command. While the command is being handled it pauses itself, then
/// resumes listening. A tap can force a capture without the wake word.
///
/// Apple's recognition tasks top out around a minute, so idle sessions are
/// rotated automatically to stay always-on.
@MainActor
final class WakeWordEngine {

    enum Mode { case stopped, listening, capturing, paused }

    // Owner callbacks.
    var onWake: () -> Void = {}
    var onPartialCommand: (String) -> Void = { _ in }
    var onCommand: (String) -> Void = { _ in }
    var onUnavailable: (String) -> Void = { _ in }

    private(set) var mode: Mode = .stopped

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var transcript = ""
    private var commandStart: String.Index?   // where the command begins after "Ace"
    private var lastChange = Date()
    private var wakeTime = Date()
    private var sessionStart = Date()
    private var monitor: Task<Void, Never>?

    // Matches "ace", "hey ace", "ace's", "aces" as a whole word.
    private let wakePattern = try! NSRegularExpression(
        pattern: "\\b(hey\\s+)?ace('s|s)?\\b", options: [.caseInsensitive])

    // Timing
    private let commandSilence: TimeInterval = 1.5    // quiet after a command → send
    private let noCommandTimeout: TimeInterval = 6    // said "Ace" but nothing followed
    private let sessionRotate: TimeInterval = 50      // restart before the ~1-min limit

    // MARK: Authorization

    func requestAuthorization() async -> Bool {
        let speechOK = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speechOK else { return false }
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            AVCaptureDevice.requestAccess(for: .audio) { c.resume(returning: $0) }
        }
    }

    // MARK: Lifecycle

    func start() {
        guard mode == .stopped || mode == .paused else { return }
        guard let recognizer, recognizer.isAvailable else {
            onUnavailable("Speech recognition isn't available right now.")
            return
        }
        startSession()
        mode = .listening
        startMonitor()
    }

    func stop() {
        monitor?.cancel(); monitor = nil
        tearDownSession()
        mode = .stopped
    }

    /// Manual trigger: capture a command immediately, skipping the wake word.
    func forceCapture() {
        if mode == .stopped || mode == .paused { start() }
        guard mode == .listening || mode == .capturing else { return }
        beginCapture(from: transcript.endIndex)
    }

    /// Resume idle wake-word listening after a reply has been handled.
    func resumeListening() {
        guard mode == .paused || mode == .stopped else { return }
        start()
    }

    // MARK: Session

    private func startSession() {
        tearDownSession()
        transcript = ""
        commandStart = nil
        sessionStart = Date()
        lastChange = Date()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = audioEngine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            onUnavailable("Couldn't start the microphone: \(error.localizedDescription)")
            return
        }

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in self?.handle(result: result, error: error) }
        }
    }

    private func tearDownSession() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let newText = result.bestTranscription.formattedString
            if newText != transcript {
                transcript = newText
                lastChange = Date()
                process()
            }
        }
        // If the task ended (final or error) while we still want to listen, the
        // monitor will rotate the session; nothing to do here.
    }

    private func process() {
        switch mode {
        case .listening:
            // Look for the wake word; command begins right after it.
            let range = NSRange(transcript.startIndex..., in: transcript)
            if let match = wakePattern.firstMatch(in: transcript, range: range),
               let r = Range(match.range, in: transcript) {
                beginCapture(from: r.upperBound)
            }
        case .capturing:
            onPartialCommand(currentCommand())
        default:
            break
        }
    }

    private func beginCapture(from index: String.Index) {
        commandStart = index
        wakeTime = Date()
        lastChange = Date()
        mode = .capturing
        onWake()
        onPartialCommand(currentCommand())
    }

    private func currentCommand() -> String {
        guard let start = commandStart, start <= transcript.endIndex else { return "" }
        return String(transcript[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Monitor loop

    private func startMonitor() {
        monitor?.cancel()
        monitor = Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self, !Task.isCancelled else { return }
                if self.tickMonitor() { return }
            }
        }
    }

    /// Returns true if the monitor should stop.
    private func tickMonitor() -> Bool {
        let now = Date()
        switch mode {
        case .stopped:
            return true
        case .capturing:
            let command = currentCommand()
            if !command.isEmpty && now.timeIntervalSince(lastChange) > commandSilence {
                finalizeCommand(command)
            } else if command.isEmpty && now.timeIntervalSince(wakeTime) > noCommandTimeout {
                // Heard "Ace" but no request followed — go back to idle.
                startSession(); mode = .listening
            }
        case .listening:
            // Rotate idle sessions so we never hit the ~1-minute task limit, and
            // recover if the task quietly ended.
            if now.timeIntervalSince(sessionStart) > sessionRotate || task == nil {
                startSession(); mode = .listening
            }
        case .paused:
            break
        }
        return false
    }

    private func finalizeCommand(_ command: String) {
        tearDownSession()
        mode = .paused                 // stop listening while the reply is handled
        onCommand(command)
    }
}
