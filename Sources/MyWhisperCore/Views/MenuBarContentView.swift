// Defines the menu bar popup content for language selection, last result, history, and settings.
import AppKit
import SwiftUI

struct MenuBarContentView: View {
    let model: AppModel

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Section("Language") {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    model.updateLanguage(language)
                } label: {
                    selectionRow(
                        title: language.menuTitle,
                        isSelected: model.settings.selectedLanguage == language
                    )
                }
            }
        }

        Divider()

        Section("Text Polish") {
            ForEach(model.textPolishProfiles) { profile in
                Button {
                    model.updateTextPolishProfile(profile.id)
                } label: {
                    selectionRow(
                        title: profileMenuTitle(for: profile),
                        isSelected: model.selectedTextPolishProfile.id == profile.id
                    )
                }
                .disabled(!model.isTextPolishProfileSelectable(profile))
            }
        }

        Divider()

        Text(model.menuStatusText)
            .foregroundStyle(.secondary)

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

    @ViewBuilder
    private func selectionRow(title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)

            if isSelected {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }
}

#Preview("Menu Bar Content") {
    MenuBarContentView(model: .preview())
        .padding(18)
        .frame(width: 300)
}
