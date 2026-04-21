// Loads and saves the persisted transcription history JSON file.
import Foundation
import OSLog

private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "HistoryStore")

final class HistoryStore {
    func load() -> [TranscriptionRecord] {
        do {
            let data = try Data(contentsOf: PersistencePaths.historyURL)
            let records = try JSONDecoder().decode([TranscriptionRecord].self, from: data)
            return records.sorted { $0.timestamp > $1.timestamp }
        } catch {
            if (error as NSError).code != NSFileReadNoSuchFileError {
                logger.error("Failed to load history: \(error)")
            }
            return []
        }
    }

    func save(_ records: [TranscriptionRecord]) throws {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: PersistencePaths.historyURL, options: .atomic)
        } catch {
            logger.error("Failed to save history: \(error)")
            throw error
        }
    }
}
