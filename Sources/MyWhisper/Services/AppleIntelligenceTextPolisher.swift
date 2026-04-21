// Uses Foundation Models to rewrite dictated text into clearer written prose.
import Foundation
import FoundationModels

protocol AppleIntelligenceTextPolishing: Sendable {
    func availability(for language: AppLanguage) -> AppleIntelligenceStatus
    func polish(_ rawText: String, language: AppLanguage, profile: TextPolishProfile) async throws -> String
}

struct AppleIntelligenceTextPolisher: AppleIntelligenceTextPolishing, Sendable {
    private let model: SystemLanguageModel

    init(model: SystemLanguageModel = SystemLanguageModel(
        useCase: .general,
        guardrails: .permissiveContentTransformations
    )) {
        self.model = model
    }

    func availability(for language: AppLanguage) -> AppleIntelligenceStatus {
        switch model.availability {
        case .available:
            guard model.supportsLocale(language.locale) else {
                return .unavailable(.unsupportedLanguage(language))
            }

            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(.appleIntelligenceNotEnabled)
        case .unavailable(.modelNotReady):
            return .unavailable(.modelNotReady)
        @unknown default:
            return .unavailable(.unknown)
        }
    }

    func polish(_ rawText: String, language: AppLanguage, profile: TextPolishProfile) async throws -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let session = LanguageModelSession(
            model: model,
            instructions: sessionInstructions(for: profile, language: language)
        )

        let response = try await session.respond(
            to: prompt(for: trimmed),
            options: GenerationOptions(sampling: .greedy)
        )

        let polishedText = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !polishedText.isEmpty else {
            throw AppleIntelligenceTextPolisherError.emptyResponse
        }

        return polishedText
    }

    func sessionInstructions(for profile: TextPolishProfile, language: AppLanguage) -> String {
        """
        You rewrite dictated text into polished written text.
        Requirements:
        - Keep the response in the same language as the input text.
        - Preserve the original meaning and tone.
        - Do not add new facts, examples, or explanations.
        - Remove spoken-language scaffolding only when it improves readability.
        - Return only the final rewritten text.
        User style instructions:
        \(profile.prompt)
        """
    }

    func prompt(for rawText: String) -> String {
        """
        Rewrite this transcription:

        \(rawText)
        """
    }
}

private enum AppleIntelligenceTextPolisherError: LocalizedError {
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "Apple Intelligence returned an empty rewrite."
        }
    }
}
