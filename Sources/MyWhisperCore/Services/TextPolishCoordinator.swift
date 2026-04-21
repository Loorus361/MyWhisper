// Routes text polishing through the selected profile backend and exposes availability checks.
import Foundation

protocol TextPolishCoordinating: Sendable {
    func appleIntelligenceStatus(for language: AppLanguage) -> AppleIntelligenceStatus
    func availability(for profile: TextPolishProfile, language: AppLanguage) -> AppleIntelligenceStatus
    func resolvedProfileID(in settings: AppSettings) -> TextPolishProfileID
    func polish(_ rawText: String, language: AppLanguage, profile: TextPolishProfile) async throws -> String
}

struct TextPolishCoordinator: TextPolishCoordinating, Sendable {
    private let deterministicPolisher: any DeterministicTextPolishing
    private let appleIntelligencePolisher: any AppleIntelligenceTextPolishing

    init(
        deterministicPolisher: any DeterministicTextPolishing = DeterministicTextPolisher(),
        appleIntelligencePolisher: any AppleIntelligenceTextPolishing = AppleIntelligenceTextPolisher()
    ) {
        self.deterministicPolisher = deterministicPolisher
        self.appleIntelligencePolisher = appleIntelligencePolisher
    }

    func appleIntelligenceStatus(for language: AppLanguage) -> AppleIntelligenceStatus {
        appleIntelligencePolisher.availability(for: language)
    }

    func availability(for profile: TextPolishProfile, language: AppLanguage) -> AppleIntelligenceStatus {
        switch profile.backend {
        case .deterministic:
            return .available
        case .appleIntelligence:
            return appleIntelligenceStatus(for: language)
        }
    }

    func resolvedProfileID(in settings: AppSettings) -> TextPolishProfileID {
        let selectedProfile = settings.selectedTextPolishProfile

        switch availability(for: selectedProfile, language: settings.selectedLanguage) {
        case .available:
            return selectedProfile.id
        case .unavailable:
            return .clean
        }
    }

    func polish(_ rawText: String, language: AppLanguage, profile: TextPolishProfile) async throws -> String {
        switch profile.backend {
        case .deterministic:
            return deterministicPolisher.polish(rawText, language: language)
        case .appleIntelligence:
            return try await appleIntelligencePolisher.polish(rawText, language: language, profile: profile)
        }
    }
}
