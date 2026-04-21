// Describes whether Apple Intelligence text polish is usable for the selected language.
import Foundation

enum AppleIntelligenceStatus: Equatable {
    case available
    case unavailable(UnavailableReason)

    enum UnavailableReason: Equatable {
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
        case unsupportedLanguage(AppLanguage)
        case unknown
    }

    var isAvailable: Bool {
        if case .available = self {
            return true
        }

        return false
    }

    func displayText(for language: AppLanguage) -> String {
        switch self {
        case .available:
            return "Ready for \(language.menuTitle)"
        case .unavailable(.deviceNotEligible):
            return "This Mac does not support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings to use Rewrite or Custom."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is not ready yet on this Mac."
        case .unavailable(.unsupportedLanguage(let unsupportedLanguage)):
            return "Apple Intelligence text polish does not support \(unsupportedLanguage.menuTitle) yet."
        case .unavailable(.unknown):
            return "Apple Intelligence text polish is unavailable right now."
        }
    }

    func fallbackMessage(for profileName: String, language: AppLanguage) -> String {
        let reasonText: String

        switch self {
        case .available:
            reasonText = "Apple Intelligence is ready."
        case .unavailable(.deviceNotEligible):
            reasonText = "this Mac does not support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            reasonText = "Apple Intelligence is turned off in System Settings."
        case .unavailable(.modelNotReady):
            reasonText = "Apple Intelligence is not ready yet on this Mac."
        case .unavailable(.unsupportedLanguage(let unsupportedLanguage)):
            reasonText = "Apple Intelligence text polish does not support \(unsupportedLanguage.menuTitle) yet."
        case .unavailable(.unknown):
            reasonText = "Apple Intelligence text polish is unavailable right now."
        }

        return "\(profileName) switched to Clean because \(reasonText)"
    }
}
