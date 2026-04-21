// Defines the menu bar popup content for language selection, last result, history, and settings.
import AppKit
import SwiftUI

struct MenuBarContentView: View {
    let model: AppModel

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

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

        Menu("Text Polish") {
            ForEach(model.textPolishProfiles) { profile in
                Button {
                    model.updateTextPolishProfile(profile.id)
                } label: {
                    HStack {
                        Text(profileMenuTitle(for: profile))
                        if model.selectedTextPolishProfile.id == profile.id {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .disabled(!model.isTextPolishProfileSelectable(profile))
            }
        }

        Divider()

        Text(model.menuStatusText)
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
            AppWindowPositioner.bringForward(role: .history)
        }

        Button("Settings") {
            openSettings()
            AppWindowPositioner.bringForward(role: .settings)
        }

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

    private func profileMenuTitle(for profile: TextPolishProfile) -> String {
        guard !model.isTextPolishProfileSelectable(profile) else {
            return profile.name
        }

        return "\(profile.name) (Unavailable)"
    }
}
