// Loads and saves the persisted app settings JSON file.
import Foundation
import OSLog

private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "AppSettingsStore")

final class AppSettingsStore {
    func load() -> AppSettings {
        do {
            let data = try Data(contentsOf: PersistencePaths.settingsURL)
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)
            let normalizedData = try JSONEncoder().encode(settings)

            if normalizedData != data {
                try normalizedData.write(to: PersistencePaths.settingsURL, options: .atomic)
            }

            return settings
        } catch {
            if (error as NSError).code != NSFileReadNoSuchFileError {
                logger.error("Failed to load settings: \(error)")
            }
            return AppSettings()
        }
    }

    func save(_ settings: AppSettings) {
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: PersistencePaths.settingsURL, options: .atomic)
        } catch {
            logger.error("Failed to save settings: \(error)")
        }
    }
}
