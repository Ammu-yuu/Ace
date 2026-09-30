import Foundation

/// Cloud brain using Anthropic's Messages API (Claude). Fast, high-quality
/// replies over the network.
///
/// Requires `ANTHROPIC_API_KEY` in `.env`. The model is configurable via
/// `ANTHROPIC_MODEL`; the default is a fast, inexpensive Haiku model, which suits
/// a chatty desktop pet. On any failure it throws a `BrainError` with a message
/// the UI shows in the speech bubble.
final class AnthropicBrain: BrainAdapter {

    private let apiKey: String
    private let model: String
    private let maxTokens = 300

    private let systemPrompt = """
    You are Ace, a laid-back but warm little companion who lives on the user's \
    desktop. You help with quick things: fixing spelling and grammar, casual \
    conversation, and reminders. Keep replies short and natural — usually one or \
    two sentences — because they may be read aloud. Be friendly and a touch \
    playful, never long-winded.
    """

    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }

    func reply(to userText: String, history: [BrainMessage]) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw BrainError.badConfig
        }

        // `history` already ends with the current user message (the view model
        // appends it before calling). The system prompt is sent separately.
        var messages: [[String: Any]] = []
        for m in history {
            switch m.role {
            case .system: continue
            case .user: messages.append(["role": "user", "content": m.text])
            case .assistant: messages.append(["role": "assistant", "content": m.text])
            }
        }
        if messages.isEmpty {
            messages.append(["role": "user", "content": userText])
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": messages
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw BrainError.unreachable
        }

        guard let http = response as? HTTPURLResponse else { throw BrainError.unreachable }
        if http.statusCode == 401 { throw BrainError.unauthorized }
        guard http.statusCode == 200 else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["error"] as? [String: Any],
               let message = err["message"] as? String {
                throw BrainError.api(message)
            }
            throw BrainError.http(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw BrainError.badResponse
        }
        let text = content.compactMap { $0["text"] as? String }.joined()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BrainError.badResponse }
        return trimmed
    }
}
