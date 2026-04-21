// Defines the fixed text polish profile identifiers persisted in user settings.
import Foundation

enum TextPolishProfileID: String, Codable, CaseIterable, Identifiable {
    case clean
    case rewrite
    case custom

    var id: String { rawValue }
}
