import AppKit
import SwiftUI

struct MenuBarContentView: View {
    let model: AppModel

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Menu("Language") {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    model.updateLanguage(language)
                } label: {
                    HStack {
                        Text(language.menuTitle)
                        if model.settings.selectedLanguage == language {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Divider()

        Text(model.dictationState == .idle ? "Ready" : model.overlayStatusText)
            .foregroundStyle(.secondary)

        Divider()

        Section("Last Inserted") {
            if let lastRecord = model.lastRecord {
                Text(lastRecord.finalText)
                    .lineLimit(4)

                Button("Copy Last Inserted") {
                    model.copyLastFinalText()
                }
            } else {
                Text("Nothing inserted yet.")
                    .foregroundStyle(.secondary)
            }
        }

        Divider()

        Button("Open History") {
            openWindow(id: AppConstants.historyWindowID)
            NSApp.activate(ignoringOtherApps: true)
        }

        SettingsLink()

        if let lastErrorMessage = model.lastErrorMessage {
            Divider()
            Text(lastErrorMessage)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Divider()

        Button("Quit MyWhisper") {
            NSApp.terminate(nil)
        }
    }
}
