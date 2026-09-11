import AVFoundation

/// Built-in macOS text-to-speech (`AVSpeechSynthesizer`). Free, offline, always
/// available — used on its own, or as the fallback when ElevenLabs is missing or
/// a call fails.
/// Confined to the main thread in practice; `@unchecked Sendable` documents that
/// we take responsibility for its thread-safety rather than the compiler.
final class AppleTTS: NSObject, TextToSpeech, AVSpeechSynthesizerDelegate, @unchecked Sendable {

    private let synthesizer = AVSpeechSynthesizer()
    private var completion: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, completion: @escaping () -> Void) {
        synthesizer.stopSpeaking(at: .immediate)
        self.completion = completion

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        fireCompletion()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        fireCompletion()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        fireCompletion()
    }

    private func fireCompletion() {
        let c = completion
        completion = nil
        c?()
    }
}
