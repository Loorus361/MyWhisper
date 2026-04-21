// Defines the runtime backend used by a text polish profile.
import Foundation

enum TextPolishBackend: String, Codable, Equatable {
    case deterministic
    case appleIntelligence

    var displayName: String {
        switch self {
        case .deterministic:
            return "Local"
        case .appleIntelligence:
            return "Apple Intelligence"
        }
    }
}
