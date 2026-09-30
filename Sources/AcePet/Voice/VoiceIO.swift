import Foundation

// Speech-to-text is handled by `WakeWordEngine` (continuous, on-device,
// wake-word driven). See Sources/AcePet/Voice/WakeWordEngine.swift.

/// Text → spoken audio. Two implementations: `AppleTTS` (built-in macOS voice,
/// free/offline) and `ElevenLabsTTS` (a chosen cloud voice). `completion` fires
/// when playback finishes (or immediately if it can't speak), so the pet can
/// return to roaming once it's done "speaking".
protocol TextToSpeech: AnyObject {
    func speak(_ text: String, completion: @escaping () -> Void)
    func stop()
}
