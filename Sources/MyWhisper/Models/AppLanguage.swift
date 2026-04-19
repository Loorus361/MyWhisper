import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case german
    case englishUS

    var id: String { rawValue }

    var shortCode: String {
        switch self {
        case .german:
            return "DE"
        case .englishUS:
            return "EN"
        }
    }

    var menuTitle: String {
        switch self {
        case .german:
            return "Deutsch"
        case .englishUS:
            return "English (US)"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .german:
            return "de-DE"
        case .englishUS:
            return "en-US"
        }
    }

    var locale: Locale {
        Locale(identifier: localeIdentifier)
    }
}
