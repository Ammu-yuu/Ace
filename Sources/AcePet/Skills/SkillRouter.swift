import Foundation

/// A free, built-in capability that can answer certain spoken commands without
/// any language model (so it costs nothing and needs no API key).
protocol Skill: Sendable {
    /// Return a spoken reply if this skill handles the command, else nil.
    func handle(_ command: String) async -> String?
}

/// Tries each skill in turn; the first that handles the command wins. Anything
/// unhandled returns nil so the caller can fall back to the language-model brain.
final class SkillRouter: Sendable {
    private let skills: [Skill]

    init(skills: [Skill] = [DictionarySkill()]) {
        self.skills = skills
    }

    func handle(_ command: String) async -> String? {
        for skill in skills {
            if let reply = await skill.handle(command) {
                return reply
            }
        }
        return nil
    }
}
