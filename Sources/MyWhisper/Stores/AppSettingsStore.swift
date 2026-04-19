// Loads and saves the persisted app settings JSON file.
import Foundation

final class AppSettingsStore {
    func load() -> AppSettings {
        do {
            let data = try Data(contentsOf: PersistencePaths.settingsURL)
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            return AppSettings()
        }
    }

    func save(_ settings: AppSettings) {
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: PersistencePaths.settingsURL, options: .atomic)
        } catch {
            return
        }
    }
}
