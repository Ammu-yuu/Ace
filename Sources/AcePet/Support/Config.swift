import Foundation

/// Lightweight configuration / secrets loader.
///
/// Values are resolved in this order (first hit wins):
///  1. The process environment — handy for `swift run` (`FOO=bar swift run`).
///  2. A `.env` file, searched in: the project root (its path is known at compile
///     time, so this works from the built `.app` too on this machine),
///     `~/.config/ace/.env`, then the current directory.
///
/// `.env` is gitignored — never commit keys.
enum Config {

    static func value(_ key: String) -> String? {
        if let v = ProcessInfo.processInfo.environment[key], !v.isEmpty { return v }
        if let v = dotenv[key], !v.isEmpty { return v }
        return nil
    }

    private static let dotenv: [String: String] = loadDotenv()

    private static func loadDotenv() -> [String: String] {
        for url in candidateFiles() {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            return parse(text)          // first existing file wins
        }
        return [:]
    }

    private static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            var val = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if val.count >= 2,
               (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                val = String(val.dropFirst().dropLast())
            }
            if result[key] == nil { result[key] = val }
        }
        return result
    }

    private static func candidateFiles() -> [URL] {
        var urls: [URL] = []

        // .../Sources/AcePet/Support/Config.swift → up 4 → project root
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Support
            .deletingLastPathComponent()   // AcePet
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // <root>
        urls.append(root.appendingPathComponent(".env"))

        let home = FileManager.default.homeDirectoryForCurrentUser
        urls.append(home.appendingPathComponent(".config/ace/.env"))

        urls.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env"))
        return urls
    }
}
