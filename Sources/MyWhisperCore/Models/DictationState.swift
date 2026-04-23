// Enumerates the high-level runtime states shown in the menu bar.
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


}
