// Presents the settings form for language defaults, permissions, storage, and roadmap notes.
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Input") {
                Picker(
                    "Default Language",
                    selection: Binding(
                        get: { model.settings.selectedLanguage },
                        set: { model.updateLanguage($0) }
                    )
                ) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.menuTitle).tag(language)
                    }
                }

                LabeledContent("Shortcut", value: model.hotkeyDisplay)
                LabeledContent("Profile", value: model.activeProfileName)

                Text("MyWhisper uses the current macOS default input device. Raw and final text are stored locally in the history.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Permissions") {
                PermissionRow(
                    title: "Microphone",
                    state: model.permissionSnapshot.microphone
                ) {
                    Task { await model.requestMicrophonePermission() }
                }

                PermissionRow(
                    title: "Speech Recognition",
                    state: model.permissionSnapshot.speech
                ) {
                    Task { await model.requestSpeechPermission() }
                }

                PermissionRow(
                    title: "Accessibility",
                    state: model.permissionSnapshot.accessibility
                ) {
                    model.requestAccessibilityPermission()
                }
            }

            Section("Storage") {
                Text("History is stored locally with unlimited retention until you delete it manually.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Roadmap") {
                Text("Later versions can add Apple on-device polish, Cloud polish, custom modes, and richer history tools.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

private struct PermissionRow: View {
    let title: String
    let state: PermissionState
    let action: () -> Void

    var body: some View {
        HStack {
            Label(title, systemImage: state.symbolName)
            Spacer()
            Text(state.label)
                .foregroundStyle(.secondary)
            Button(state == .granted ? "Granted" : "Allow", action: action)
                .disabled(state == .granted)
        }
    }
}
