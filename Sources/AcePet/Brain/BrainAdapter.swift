import Foundation

/// A single turn in the conversation.
struct BrainMessage: Sendable {
    enum Role: Sendable { case system, user, assistant }
    let role: Role
    let text: String
}

/// The "brain" is whatever produces a reply to the user. Keeping this behind a
/// protocol means the UI/voice loop never cares whether the answer comes from a
/// stub, a local model, the Claude API, or OpenClaw — we just swap the adapter.
///
/// Wired up for real in **Step D**.
protocol BrainAdapter: AnyObject, Sendable {
    /// Produce a reply to `userText`, given recent conversation `history`
    /// (most recent last). Implementations should be safe to call repeatedly.
    func reply(to userText: String, history: [BrainMessage]) async throws -> String
}

/// Default placeholder brain so the whole app runs end-to-end before any real
/// AI backend is connected. It just echoes, so you can verify the voice loop
/// and speech bubble independently of the model.
final class StubBrain: BrainAdapter {
    func reply(to userText: String, history: [BrainMessage]) async throws -> String {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "I didn't catch that — try again?"
        }
        return "(stub brain) You said: “\(trimmed)”. Connect a real brain in Step D and I'll actually help."
    }
}
