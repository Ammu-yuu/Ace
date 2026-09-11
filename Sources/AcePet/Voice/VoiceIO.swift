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

/// Text → spoken audio. Two implementations: `AppleTTS` (built-in macOS voice,
/// free/offline) and `ElevenLabsTTS` (a chosen cloud voice). `completion` fires
/// when playback finishes (or immediately if it can't speak), so the pet can
/// return to roaming once it's done "speaking".
protocol TextToSpeech: AnyObject {
    func speak(_ text: String, completion: @escaping () -> Void)
    func stop()
}
