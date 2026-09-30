import Foundation

/// Reads a **public-domain** book aloud, fetched from Project Gutenberg via the
/// free gutendex catalog API (no key). Public-domain text only — nothing
/// copyrighted. Reads paragraph-sized chunks so it's smooth and stoppable.
@MainActor
final class BookReader {

    private let tts: TextToSpeech
    private var chunks: [String] = []
    private var index = 0
    private(set) var isReading = false

    /// Fired when the book finishes on its own (not when stopped manually).
    var onFinished: () -> Void = {}
    /// Fired with each chunk as it starts, so the UI can show what's being read.
    var onChunk: (String) -> Void = { _ in }

    init(tts: TextToSpeech) {
        self.tts = tts
    }

    /// Is `command` a "read me …" request?
    func isReadRequest(_ command: String) -> Bool {
        let lower = command.lowercased()
        return lower.hasPrefix("read ") || lower.hasPrefix("read me") || lower == "read"
            || lower.contains(" read me ")
    }

    /// Start reading. Returns a short intro line for the bubble. On failure it
    /// returns an explanatory line and does not enter reading mode.
    func start(_ command: String) async -> String {
        let query = extractQuery(from: command)
        do {
            guard let book = try await search(query) else {
                return "I couldn't find a public-domain book like that."
            }
            let text = try await fetchText(book.textURL)
            let body = chunkize(stripBoilerplate(text))
            guard !body.isEmpty else {
                return "I found “\(book.title)” but couldn't read its text."
            }

            let byline = book.author.map { " by \($0)" } ?? ""
            let intro = "Okay — reading “\(book.title)”\(byline). Tap me to stop."
            chunks = [intro] + body
            index = 0
            isReading = true
            readNext()
            return intro
        } catch {
            return "I couldn't reach the library just now — check your connection."
        }
    }

    func stop() {
        isReading = false
        chunks = []
        index = 0
        tts.stop()
    }

    private func readNext() {
        guard isReading, index < chunks.count else {
            let finished = isReading
            isReading = false
            chunks = []
            if finished { onFinished() }
            return
        }
        let chunk = chunks[index]
        index += 1
        onChunk(chunk)
        tts.speak(chunk) { [weak self] in
            Task { @MainActor in
                guard let self, self.isReading else { return }
                self.readNext()
            }
        }
    }

    // MARK: - Parsing helpers

    private func extractQuery(from command: String) -> String {
        var t = command.lowercased()
        for p in ["read me the book", "read me a book", "read me the story", "read me a story",
                  "read me the poem", "read me the", "read me a", "read me", "read the book",
                  "read the story", "read the", "read a book", "read a story", "read a", "read",
                  "please", " to me", " aloud", "book", "story", "poem", "called", "titled"] {
            t = t.replacingOccurrences(of: p, with: " ")
        }
        let q = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? "fairy tales" : q     // a pleasant default when no title is given
    }

    private struct Book { let title: String; let author: String?; let textURL: URL }

    private func search(_ query: String) async throws -> Book? {
        let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://gutendex.com/books?search=\(escaped)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return nil }

        for result in results {
            let title = (result["title"] as? String) ?? "a book"
            let author = (result["authors"] as? [[String: Any]])?.first?["name"] as? String
            guard let formats = result["formats"] as? [String: String] else { continue }
            if let entry = formats.first(where: { $0.key.hasPrefix("text/plain") && !$0.value.hasSuffix(".zip") }),
               let textURL = URL(string: entry.value) {
                return Book(title: title, author: author, textURL: textURL)
            }
        }
        return nil
    }

    private func fetchText(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    /// Strip Project Gutenberg's header/footer so only the book text is read.
    private func stripBoilerplate(_ text: String) -> String {
        var body = text
        if let start = text.range(of: "*** START OF", options: .caseInsensitive) {
            let after = text[start.lowerBound...]
            if let newline = after.firstIndex(of: "\n") {
                body = String(after[after.index(after: newline)...])
            }
        }
        if let end = body.range(of: "*** END OF", options: .caseInsensitive) {
            body = String(body[..<end.lowerBound])
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Merge lines into paragraph-sized chunks (~600 chars) for smooth playback.
    private func chunkize(_ body: String) -> [String] {
        let paragraphs = body
            .components(separatedBy: "\n\n")
            .map { $0.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var current = ""
        for paragraph in paragraphs {
            if current.count + paragraph.count > 600, !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : " ") + paragraph
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
