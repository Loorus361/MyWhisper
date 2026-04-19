// Stores the user-configurable app settings that persist between launches.
import Foundation

struct AppSettings: Codable, Equatable {
    var selectedLanguage: AppLanguage = .german
}
