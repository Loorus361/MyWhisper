// Loads and saves the persisted transcription history JSON file.
import Foundation

final class HistoryStore {
    func load() -> [TranscriptionRecord] {
        do {
            let data = try Data(contentsOf: PersistencePaths.historyURL)
            let records = try JSONDecoder().decode([TranscriptionRecord].self, from: data)
            return records.sorted { $0.timestamp > $1.timestamp }
        } catch {
            return []
        }
    }

    func save(_ records: [TranscriptionRecord]) {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: PersistencePaths.historyURL, options: .atomic)
        } catch {
            return
        }
    }
}
