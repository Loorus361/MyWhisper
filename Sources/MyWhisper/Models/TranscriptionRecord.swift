import Foundation

struct TranscriptionRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let language: AppLanguage
    let profileName: String
    let rawText: String
    let finalText: String

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        language: AppLanguage,
        profileName: String = "Standard",
        rawText: String,
        finalText: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.language = language
        self.profileName = profileName
        self.rawText = rawText
        self.finalText = finalText
    }
}
