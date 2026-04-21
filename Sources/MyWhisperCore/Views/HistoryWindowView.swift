// Shows the grouped transcription history and a side-by-side raw versus final detail view.
import SwiftUI

struct HistoryWindowView: View {
    let model: AppModel

    @State private var selectedRecordID: UUID?

    private var selectedRecord: TranscriptionRecord? {
        if let selectedRecordID {
            return model.history.first { $0.id == selectedRecordID } ?? model.history.first
        }

        return model.history.first
    }

    var body: some View {
        NavigationSplitView {
            Group {
                if model.history.isEmpty {
                    ContentUnavailableView(
                        "No History Yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Your dictation sessions will appear here after the first successful insert.")
                    )
                } else {
                    List {
                        ForEach(model.historyGroups) { day in
                            Section(day.title) {
                                ForEach(day.sessions) { session in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(session.title)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        ForEach(session.records) { record in
                                            Button {
                                                selectedRecordID = record.id
                                            } label: {
                                                HistoryRecordRow(
                                                    record: record,
                                                    isSelected: selectedRecordID == record.id
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .navigationTitle("History")
        } detail: {
            Group {
                if let record = selectedRecord {
                    HistoryDetailView(record: record)
                } else {
                    ContentUnavailableView(
                        "Select a Record",
                        systemImage: "text.alignleft",
                        description: Text("Choose a transcription from the sidebar to compare raw and polished text.")
                    )
                }
            }
            .navigationTitle("Details")
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 980, minHeight: 620)
        .onAppear {
            selectedRecordID = selectedRecordID ?? model.history.first?.id
        }
    }
}

#Preview("History Window") {
    HistoryWindowView(model: .preview())
}

#Preview("History Empty") {
    HistoryWindowView(model: .preview(history: []))
}

private struct HistoryRecordRow: View {
    let record: TranscriptionRecord
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.language.shortCode)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(record.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(record.finalText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.secondary.opacity(0.12) : Color.clear)
        )
    }
}

private struct HistoryDetailView: View {
    let record: TranscriptionRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Label(record.language.menuTitle, systemImage: "globe")
                    Text(record.profileName)
                    Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)

                HStack(alignment: .top, spacing: 16) {
                    HistoryTextCard(title: "Raw Text", bodyText: record.rawText)
                    HistoryTextCard(title: "Final Text", bodyText: record.finalText)
                }
            }
            .padding(20)
        }
    }
}

private struct HistoryTextCard: View {
    let title: String
    let bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            ScrollView {
                Text(bodyText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
