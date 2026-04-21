// Stores the user-configurable app settings that persist between launches.
import Foundation

struct AppSettings: Codable, Equatable {
    var selectedLanguage: AppLanguage
    var selectedTextPolishProfileID: TextPolishProfileID
    var textPolishProfiles: [TextPolishProfile]

    init(
        selectedLanguage: AppLanguage = .german,
        selectedTextPolishProfileID: TextPolishProfileID = .clean,
        textPolishProfiles: [TextPolishProfile] = TextPolishProfile.defaultProfiles
    ) {
        self.selectedLanguage = selectedLanguage
        self.selectedTextPolishProfileID = selectedTextPolishProfileID
        self.textPolishProfiles = TextPolishProfile.merged(with: textPolishProfiles)

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

    mutating func updatePrompt(_ prompt: String, for id: TextPolishProfileID) {
        guard let index = textPolishProfiles.firstIndex(where: { $0.id == id }) else { return }
        textPolishProfiles[index].prompt = prompt
    }

    mutating func resetPrompt(for id: TextPolishProfileID) {
        updatePrompt(TextPolishProfile.defaultProfile(for: id).prompt, for: id)
    }

    private enum CodingKeys: String, CodingKey {
        case selectedLanguage
        case selectedTextPolishProfileID
        case textPolishProfiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let selectedLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .selectedLanguage) ?? .german
        let selectedTextPolishProfileID = try container.decodeIfPresent(
            TextPolishProfileID.self,
            forKey: .selectedTextPolishProfileID
        ) ?? .clean
        let storedProfiles = try container.decodeIfPresent([TextPolishProfile].self, forKey: .textPolishProfiles) ?? []

        self.init(
            selectedLanguage: selectedLanguage,
            selectedTextPolishProfileID: selectedTextPolishProfileID,
            textPolishProfiles: storedProfiles
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedLanguage, forKey: .selectedLanguage)
        try container.encode(selectedTextPolishProfileID, forKey: .selectedTextPolishProfileID)
        try container.encode(textPolishProfiles, forKey: .textPolishProfiles)
    }
}
