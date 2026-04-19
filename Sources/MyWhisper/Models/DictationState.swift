// Enumerates the high-level runtime states shown in the menu bar and overlay UI.
import Foundation

enum DictationState: Equatable {
    case idle
    case preparing
    case listening
    case processing
    case inserted
    case error(String)

    var menuBarSymbolName: String {
        switch self {
        case .idle:
            return "mic"
        case .preparing:
            return "mic.badge.clock"
        case .listening:
            return "waveform.circle.fill"
        case .processing:
            return "hourglass"
        case .inserted:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    var overlayTitle: String {
        switch self {
        case .idle:
            return "Ready"
        case .preparing:
            return "Preparing"
        case .listening:
            return "Listening"
        case .processing:
            return "Processing"
        case .inserted:
            return "Inserted"
        case .error:
            return "Error"
        }
    }
}
