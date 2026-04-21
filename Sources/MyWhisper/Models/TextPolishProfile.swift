// Represents one persisted text polish mode and its visible prompt text.
import Foundation

struct TextPolishProfile: Codable, Equatable, Identifiable {
    let id: TextPolishProfileID
    let name: String
    let backend: TextPolishBackend
    var prompt: String

    var isPromptEditable: Bool {
        backend == .appleIntelligence
    }

    static let cleanRulesText = """
    Local cleanup only:
    - Trim surrounding whitespace.
    - Remove common filler words.
    - Capitalize the first letter.
    - Add simple closing punctuation when the result reads like a sentence.
    """

    static let defaultProfiles: [TextPolishProfile] = [
        TextPolishProfile(
            id: .clean,
            name: "Clean",
            backend: .deterministic,
            prompt: cleanRulesText
        ),
        TextPolishProfile(
            id: .rewrite,
            name: "Rewrite",
            backend: .appleIntelligence,
            prompt: """
            Rewrite the dictated text into clear, natural written prose. Remove filler words, repetitions, and spoken-language scaffolding. Preserve the original meaning and tone.
            """
        ),
        TextPolishProfile(
            id: .custom,
            name: "Custom",
            backend: .appleIntelligence,
            prompt: """
            Rewrite the dictated text so it feels concise, direct, and easy to scan. Compress repeated ideas and smooth rough spoken phrasing without adding new information.
            """
        ),
    ]

    static func defaultProfile(for id: TextPolishProfileID) -> TextPolishProfile {
        defaultProfiles.first(where: { $0.id == id })!
    }

    static func merged(with storedProfiles: [TextPolishProfile]) -> [TextPolishProfile] {
        let storedPrompts = Dictionary(uniqueKeysWithValues: storedProfiles.map { ($0.id, $0.prompt) })

        return TextPolishProfileID.allCases.map { id in
            var profile = defaultProfile(for: id)

            if let storedPrompt = storedPrompts[id] {
                profile.prompt = storedPrompt
            }

            return profile
        }
    }
}
