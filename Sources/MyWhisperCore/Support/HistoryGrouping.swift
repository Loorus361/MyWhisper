// Groups stored transcription records into day buckets and session windows for the history UI.
import Foundation

struct HistoryDayGroup: Identifiable {
    let date: Date
    let sessions: [HistorySessionGroup]

    var id: Date { date }

    var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }

        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct HistorySessionGroup: Identifiable {
    let records: [TranscriptionRecord]

    var id: Date { startDate }
    var startDate: Date { records.first?.timestamp ?? .distantPast }
    var endDate: Date { records.last?.timestamp ?? .distantPast }

    var title: String {
        "\(endDate.formatted(date: .omitted, time: .shortened)) – \(startDate.formatted(date: .omitted, time: .shortened))"
    }
}

enum HistoryGrouper {
    static func makeDayGroups(from records: [TranscriptionRecord]) -> [HistoryDayGroup] {
        let ascendingRecords = records.sorted { $0.timestamp < $1.timestamp }
        let dayBuckets = Dictionary(grouping: ascendingRecords) { record in
            Calendar.current.startOfDay(for: record.timestamp)
        }

        return dayBuckets
            .map { day, records in
                let sessions = makeSessions(from: records)
                    .reversed()
                    .map { HistorySessionGroup(records: Array($0.reversed())) }
                return HistoryDayGroup(date: day, sessions: sessions)
            }
            .sorted { $0.date > $1.date }
    }

    private static func makeSessions(from records: [TranscriptionRecord]) -> [[TranscriptionRecord]] {
        guard let first = records.first else { return [] }

        var sessions = [[first]]

        for record in records.dropFirst() {
            guard let lastTimestamp = sessions[sessions.count - 1].last?.timestamp else {
                sessions.append([record])
                continue
            }

            if record.timestamp.timeIntervalSince(lastTimestamp) <= AppConstants.sessionGap {
                sessions[sessions.count - 1].append(record)
            } else {
                sessions.append([record])
            }
        }

        return sessions
    }
}
