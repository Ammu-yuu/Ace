import Foundation

/// Microphone → text. Implemented in **Step C** with Apple's on-device `Speech`
/// framework (`SFSpeechRecognizer`) so no cloud service or API key is required.
protocol SpeechToText: AnyObject {
    /// Record a single short utterance and return its transcription.
    func transcribeOnce() async throws -> String
}

/// Text → spoken audio. Implemented in **Step E** with `AVSpeechSynthesizer`.
protocol TextToSpeech: AnyObject {
    func speak(_ text: String)
    func stop()
}

// MARK: - Placeholders (replaced in Steps C & E)

/// No-op STT so the project compiles and the wiring is visible before Step C.
final class PlaceholderSpeechToText: SpeechToText {
    func transcribeOnce() async throws -> String {
        return "(placeholder transcription — real mic input arrives in Step C)"
    }
}

/// No-op TTS placeholder; replaced by AVSpeechSynthesizer in Step E.
final class PlaceholderTextToSpeech: TextToSpeech {
    func speak(_ text: String) {
        print("[TTS placeholder] would speak: \(text)")
    }
    func stop() {}
}
