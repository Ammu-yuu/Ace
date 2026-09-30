import Foundation

/// "What does X mean?" / "define X" / "meaning of X" — answered for free via the
/// public [Free Dictionary API](https://dictionaryapi.dev) (no key, HTTPS).
struct DictionarySkill: Skill {

    private let triggers = ["define ", "definition of ", "meaning of ",
                            "what does ", "what's ", "what is the meaning of "]

    func handle(_ command: String) async -> String? {
        let lower = command.lowercased()
        guard triggers.contains(where: { lower.contains($0) }) else { return nil }

        guard let word = extractWord(from: lower) else {
            return "Which word would you like me to define?"
        }

        do {
            if let definition = try await lookup(word) {
                return "\(word.capitalized): \(definition)"
            }
            return "Hmm, I couldn't find a definition for “\(word).”"
        } catch {
            return "I couldn't reach the dictionary just now — check your connection."
        }
    }

    /// Pull the target word out of the phrase, dropping trigger words and filler.
    private func extractWord(from lower: String) -> String? {
        var text = lower
        for t in ["what is the meaning of", "what does", "what's", "definition of",
                  "meaning of", "define", "the word", "mean", "means", "?", "."] {
            text = text.replacingOccurrences(of: t, with: " ")
        }
        // The word being asked about is the last remaining significant token.
        let tokens = text.split(whereSeparator: { !$0.isLetter && $0 != "-" })
            .map(String.init)
            .filter { $0.count > 1 }
        return tokens.last
    }

    private func lookup(_ word: String) async throws -> String? {
        let escaped = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word
        guard let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(escaped)") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil   // 404 = word not found
        }

        // Response: [ { meanings: [ { partOfSpeech, definitions: [ { definition } ] } ] } ]
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = entries.first,
              let meanings = first["meanings"] as? [[String: Any]],
              let meaning = meanings.first,
              let part = meaning["partOfSpeech"] as? String,
              let definitions = meaning["definitions"] as? [[String: Any]],
              let definition = definitions.first?["definition"] as? String else {
            return nil
        }
        return "(\(part)) \(definition)"
    }
}
