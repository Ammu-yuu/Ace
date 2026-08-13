import Foundation
import Speech
import AVFoundation

/// On-device speech-to-text using Apple's `Speech` framework + `AVAudioEngine`.
///
/// Everything runs locally (no network, no API key) when the device supports
/// on-device recognition, which modern Macs do for English. Requires the app to
/// run from a bundle whose Info.plist declares `NSMicrophoneUsageDescription`
/// and `NSSpeechRecognitionUsageDescription` (see scripts/Info.plist) — a bare
/// `swift run` binary has no bundle identity and macOS will deny the mic.
final class AppleSpeechToText: SpeechToText {

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""

    private(set) var isRunning = false

    // MARK: Authorization

    func requestAuthorization() async -> Bool {
        let speechOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speechOK else { return false }

        let micOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
        return micOK
    }

    // MARK: Recognition

    func start(onUpdate: @escaping (String) -> Void) throws {
        guard let recognizer, recognizer.isAvailable else {
            throw VoiceError.recognizerUnavailable
        }

        // Fresh state for this utterance.
        latest = ""
        task?.cancel()
        task = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)   // guard against a stale tap
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRunning = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            self.latest = result.bestTranscription.formattedString
            onUpdate(self.latest)
        }
    }

    func stop() async -> String {
        guard isRunning else { return latest }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        isRunning = false

        // Give the recognizer a beat to emit its final result.
        try? await Task.sleep(nanoseconds: 400_000_000)

        task?.cancel()
        task = nil
        request = nil
        return latest
    }
}

enum VoiceError: LocalizedError {
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognition isn't available right now."
        }
    }
}
