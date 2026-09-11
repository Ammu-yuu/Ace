import AVFoundation
import Foundation

/// Speaks Ace's replies through a chosen [ElevenLabs](https://elevenlabs.io)
/// voice (cloud TTS). Needs an API key. If the key is bad, the network fails,
/// or the account is out of quota, it transparently falls back to the system
/// voice so Ace still speaks.
///
/// Note: ElevenLabs bills per character — this makes a network request per reply.
/// Audio work is dispatched to the main actor; `@unchecked Sendable` documents
/// that we manage its thread-safety.
final class ElevenLabsTTS: NSObject, TextToSpeech, AVAudioPlayerDelegate, @unchecked Sendable {

    private let apiKey: String
    private let voiceID: String
    private let modelID: String
    private let fallback: TextToSpeech

    private var player: AVAudioPlayer?
    private var completion: (() -> Void)?

    init(apiKey: String,
         voiceID: String,
         modelID: String = "eleven_multilingual_v2",
         fallback: TextToSpeech) {
        self.apiKey = apiKey
        self.voiceID = voiceID
        self.modelID = modelID
        self.fallback = fallback
        super.init()
    }

    func speak(_ text: String, completion: @escaping () -> Void) {
        self.completion = completion
        Task { await synthesizeAndPlay(text) }
    }

    func stop() {
        player?.stop()
        player = nil
        fallback.stop()
        fireCompletion()
    }

    private func synthesizeAndPlay(_ text: String) async {
        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)") else {
            useFallback(text); return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text": text,
            "model_id": modelID,
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75]
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard status == 200, !data.isEmpty else {
                log("ElevenLabs TTS failed (HTTP \(status)) — using system voice")
                useFallback(text)
                return
            }
            await MainActor.run { self.play(data) }
        } catch {
            log("ElevenLabs TTS error: \(error.localizedDescription) — using system voice")
            useFallback(text)
        }
    }

    @MainActor
    private func play(_ data: Data) {
        do {
            player = try AVAudioPlayer(data: data)
            player?.delegate = self
            player?.play()
        } catch {
            log("Couldn't play ElevenLabs audio: \(error.localizedDescription)")
            fireCompletion()
        }
    }

    /// Speak with the system voice instead, forwarding our completion.
    private func useFallback(_ text: String) {
        let c = completion
        completion = nil
        fallback.speak(text) { c?() }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        fireCompletion()
    }

    private func fireCompletion() {
        let c = completion
        completion = nil
        c?()
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
