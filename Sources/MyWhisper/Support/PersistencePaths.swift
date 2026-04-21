// Resolves the Application Support paths used for MyWhisper settings and history storage.
import Foundation

enum PersistencePaths {
    static var applicationSupportDirectory: URL {
        let fileManager = FileManager.default
        guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            preconditionFailure("Application Support directory unavailable — cannot run on this system")
        }
        let directoryURL = baseURL.appendingPathComponent(AppConstants.bundleIdentifier, isDirectory: true)

        if !fileManager.fileExists(atPath: directoryURL.path) {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        return directoryURL
    }

    static var settingsURL: URL {
        applicationSupportDirectory.appendingPathComponent("settings.json")
    }

    static var historyURL: URL {
        applicationSupportDirectory.appendingPathComponent("history.json")
    }
}
