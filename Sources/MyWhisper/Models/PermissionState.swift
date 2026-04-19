import Foundation

enum PermissionState: String, Codable {
    case notDetermined
    case granted
    case denied

    var label: String {
        switch self {
        case .notDetermined:
            return "Not requested"
        case .granted:
            return "Allowed"
        case .denied:
            return "Denied"
        }
    }

    var symbolName: String {
        switch self {
        case .notDetermined:
            return "questionmark.circle"
        case .granted:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        }
    }
}

struct PermissionSnapshot: Equatable {
    var microphone: PermissionState
    var speech: PermissionState
    var accessibility: PermissionState

    static let empty = PermissionSnapshot(
        microphone: .notDetermined,
        speech: .notDetermined,
        accessibility: .notDetermined
    )
}
