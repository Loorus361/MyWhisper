// Represents the readiness of the selected Apple speech model for the current app session.
import Foundation

enum LanguageModelStatus: Equatable {
    case idle
    case checking
    case downloading(progress: Double?)
    case ready
    case failed(String)

    var displayText: String {
        switch self {
        case .idle:
            return "Not prepared yet"
        case .checking:
            return "Checking Apple speech model..."
        case .downloading(let progress):
            guard let progress else {
                return "Downloading Apple speech model..."
            }

            let percentage = Int((progress * 100).rounded())
            return "Downloading Apple speech model (\(percentage)%)"
        case .ready:
            return "Apple speech model ready"
        case .failed(let message):
            return "Preparation failed: \(message)"
        }
    }

    var showsRetryAction: Bool {
        switch self {
        case .checking, .downloading, .failed:
            return true
        case .idle, .ready:
            return false
        }
    }

    var isRetryEnabled: Bool {
        if case .failed = self {
            return true
        }

        return false
    }
}
