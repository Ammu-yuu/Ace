import AVFoundation

/// Built-in macOS text-to-speech (`AVSpeechSynthesizer`). Free, offline, always
/// available — used on its own, or as the fallback when ElevenLabs is missing.
///
/// Voice selection (Ace wants an Irish male): an explicit `ACE_VOICE` override
/// in `.env` wins; otherwise prefer a male Irish (en-IE) voice, then any Irish
/// voice (Moira), then any English male, then the system default. Download more
/// voices in System Settings ▸ Accessibility ▸ Spoken Content ▸ Manage Voices.
///
/// Confined to the main thread in practice; `@unchecked Sendable` documents that
/// we take responsibility for its thread-safety rather than the compiler.
final class AppleTTS: NSObject, TextToSpeech, AVSpeechSynthesizerDelegate, @unchecked Sendable {

    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    private var completion: (() -> Void)?

    override init() {
        self.voice = AppleTTS.selectVoice()
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, completion: @escaping () -> Void) {
        synthesizer.stopSpeaking(at: .immediate)
        self.completion = completion

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: "en-IE")
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

    // MARK: - Voice selection

    private static func selectVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()

        // 1. Explicit override: match by identifier, exact name, name substring, or language.
        if let pref = Config.value("ACE_VOICE")?.lowercased(), !pref.isEmpty {
            if let v = voices.first(where: {
                $0.identifier.lowercased() == pref
                || $0.name.lowercased() == pref
                || $0.name.lowercased().contains(pref)
                || $0.language.lowercased() == pref
            }) { return v }
        }

        let english = voices.filter { $0.language.hasPrefix("en") }
        // 2. Male Irish → 3. any Irish → 4. any English male → 5. default.
        return best(voices, language: "en-IE", gender: .male)
            ?? best(voices, language: "en-IE", gender: nil)
            ?? best(english, language: nil, gender: .male)
            ?? AVSpeechSynthesisVoice(language: "en-IE")
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Highest-quality voice matching the filters (premium > enhanced > default).
    private static func best(_ voices: [AVSpeechSynthesisVoice],
                             language: String?,
                             gender: AVSpeechSynthesisVoiceGender?) -> AVSpeechSynthesisVoice? {
        voices
            .filter { language == nil || $0.language == language }
            .filter { gender == nil || $0.gender == gender! }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
            .first
    }
}
