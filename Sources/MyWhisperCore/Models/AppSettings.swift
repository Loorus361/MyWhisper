// Stores the user-configurable app settings that persist between launches.
import Foundation

struct AppSettings: Codable, Equatable {
    var selectedLanguage: AppLanguage
    var selectedTextPolishProfileID: TextPolishProfileID
    var textPolishProfiles: [TextPolishProfile]
    var dictationVocabulary: [String]

    init(
        selectedLanguage: AppLanguage = .german,
        selectedTextPolishProfileID: TextPolishProfileID = .clean,
        textPolishProfiles: [TextPolishProfile] = TextPolishProfile.defaultProfiles,
        dictationVocabulary: [String] = Self.defaultDictationVocabulary
    ) {
        self.selectedLanguage = selectedLanguage
        self.selectedTextPolishProfileID = selectedTextPolishProfileID
        self.textPolishProfiles = TextPolishProfile.merged(with: textPolishProfiles)
        self.dictationVocabulary = Self.normalizedVocabulary(from: dictationVocabulary)

        if textPolishProfile(for: selectedTextPolishProfileID) == nil {
            self.selectedTextPolishProfileID = .clean
        }
    }

    var selectedTextPolishProfile: TextPolishProfile {
        textPolishProfile(for: selectedTextPolishProfileID) ?? TextPolishProfile.defaultProfile(for: .clean)
    }

    func textPolishProfile(for id: TextPolishProfileID) -> TextPolishProfile? {
        textPolishProfiles.first(where: { $0.id == id })
    }

    mutating func updateSystemPrompt(_ systemPrompt: String, for id: TextPolishProfileID) {
        guard let index = textPolishProfiles.firstIndex(where: { $0.id == id }) else { return }
        textPolishProfiles[index].systemPrompt = systemPrompt
    }

    mutating func resetSystemPrompt(for id: TextPolishProfileID) {
        updateSystemPrompt(TextPolishProfile.defaultProfile(for: id).systemPrompt, for: id)
    }

    mutating func updatePrompt(_ prompt: String, for id: TextPolishProfileID) {
        guard let index = textPolishProfiles.firstIndex(where: { $0.id == id }) else { return }
        textPolishProfiles[index].prompt = prompt
    }

    mutating func resetPrompt(for id: TextPolishProfileID) {
        updatePrompt(TextPolishProfile.defaultProfile(for: id).prompt, for: id)
    }

    mutating func updateDictationVocabulary(_ vocabulary: [String]) {
        dictationVocabulary = Self.normalizedVocabulary(from: vocabulary)
    }

    mutating func resetDictationVocabulary() {
        dictationVocabulary = Self.defaultDictationVocabulary
    }

    static let defaultDictationVocabulary = [
        "Xcode",
        "Swift",
        "SwiftUI",
        "AppKit",
        "Codex",
        "OpenAI",
        "Whisper",
        "MenuBarExtra",
        "Accessibility",
        "clipboard",
        "Git",
        "GitHub",
        "commit",
        "branch",
        "pull request",
        "merge",
        "rebase",
        "build",
        "deploy",
        "bugfix",
        "refactor",
        "CLI",
        "API",
        "AppIntent",
        "shortcut",
    ]

    static func normalizedVocabulary(from vocabulary: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for entry in vocabulary {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { continue }

            normalized.append(trimmed)
        }

        return normalized
    }

    private enum CodingKeys: String, CodingKey {
        case selectedLanguage
        case selectedTextPolishProfileID
        case textPolishProfiles
        case dictationVocabulary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let selectedLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .selectedLanguage) ?? .german
        let selectedTextPolishProfileID = try container.decodeIfPresent(
            TextPolishProfileID.self,
            forKey: .selectedTextPolishProfileID
        ) ?? .clean
        let storedProfiles = try container.decodeIfPresent([TextPolishProfile].self, forKey: .textPolishProfiles) ?? []
        let dictationVocabulary = try container.decodeIfPresent(
            [String].self,
            forKey: .dictationVocabulary
        ) ?? Self.defaultDictationVocabulary

        self.init(
            selectedLanguage: selectedLanguage,
            selectedTextPolishProfileID: selectedTextPolishProfileID,
            textPolishProfiles: storedProfiles,
            dictationVocabulary: dictationVocabulary
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedLanguage, forKey: .selectedLanguage)
        try container.encode(selectedTextPolishProfileID, forKey: .selectedTextPolishProfileID)
        try container.encode(textPolishProfiles, forKey: .textPolishProfiles)
        try container.encode(dictationVocabulary, forKey: .dictationVocabulary)
    }
}
