import Foundation

/// Talks to a locally-running [Ollama](https://ollama.com) server — private,
/// offline, no API key. Requires Ollama to be running and the chosen model
/// pulled (e.g. `ollama pull llama3.2`).
///
/// On any connection problem it throws a `BrainError` whose message tells the
/// user exactly what to do, which the UI shows in the speech bubble.
final class OllamaBrain: BrainAdapter {

    private let host: String
    private let model: String

    private let systemPrompt = """
    You are Ace, a laid-back but warm little companion who lives on the user's \
    desktop. You help with quick things: fixing spelling and grammar, casual \
    conversation, and reminders. Keep replies short and natural — usually one or \
    two sentences — because they are spoken aloud. Be friendly and a touch \
    playful, never long-winded.
    """

    init(host: String, model: String) {
        self.host = host
        self.model = model
    }

    func reply(to userText: String, history: [BrainMessage]) async throws -> String {
        guard let url = URL(string: "\(host)/api/chat") else { throw BrainError.badConfig }

        // `history` already ends with the current user message (the view model
        // appends it before calling), so we just map it through.
        var messages: [[String: String]] = [["role": "system", "content": systemPrompt]]
        for m in history {
            let role: String
            switch m.role {
            case .user: role = "user"
            case .assistant: role = "assistant"
            case .system: role = "system"
            }
            messages.append(["role": role, "content": m.text])
        }

        let body: [String: Any] = ["model": model, "messages": messages, "stream": false]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw BrainError.unreachable
        }

        guard let http = response as? HTTPURLResponse else { throw BrainError.unreachable }
        if http.statusCode == 404 { throw BrainError.modelMissing(model) }
        guard http.statusCode == 200 else { throw BrainError.http(http.statusCode) }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw BrainError.badResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum BrainError: LocalizedError {
    case badConfig
    case unreachable
    case unauthorized
    case modelMissing(String)
    case http(Int)
    case api(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .badConfig:
            return "My brain isn't configured correctly."
        case .unreachable:
            return "I can't reach my brain — is there a connection? Check your setup."
        case .unauthorized:
            return "My API key looks invalid — check ANTHROPIC_API_KEY in your .env."
        case .modelMissing(let model):
            return "The \"\(model)\" model isn't installed yet. Run: ollama pull \(model)"
        case .http(let code):
            return "My brain returned an error (\(code))."
        case .api(let message):
            return message
        case .badResponse:
            return "I got a confusing answer from my brain."
        }
    }
}
