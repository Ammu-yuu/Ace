import Foundation

/// Microphone → text. Implemented in **Step C** with Apple's on-device `Speech`
/// framework (`SFSpeechRecognizer`) so no cloud service or API key is required.
///
/// Push-to-talk style: `start` begins live recognition (partial transcripts are
/// delivered via `onUpdate`), and `stop` finalizes and returns the transcript.
protocol SpeechToText: AnyObject {
    var isRunning: Bool { get }

    /// Ask for microphone + speech-recognition permission. Returns whether both
    /// were granted.
    func requestAuthorization() async -> Bool

    /// Begin live recognition. `onUpdate` fires with the running transcript.
    func start(onUpdate: @escaping (String) -> Void) throws

    /// Stop recognition and return the final transcript.
    func stop() async -> String
}

/// Text → spoken audio. Implemented in **Step E** with `AVSpeechSynthesizer`.
protocol TextToSpeech: AnyObject {
    func speak(_ text: String)
    func stop()
}

// MARK: - Placeholder TTS (replaced in Step E)

/// No-op TTS placeholder; replaced by AVSpeechSynthesizer in Step E.
final class PlaceholderTextToSpeech: TextToSpeech {
    func speak(_ text: String) {
        print("[TTS placeholder] would speak: \(text)")
    }
    func stop() {}
}
