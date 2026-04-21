// Presents the settings form for language defaults, permissions, polish modes, and storage.
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    @State private var dictationVocabularyDraft = ""

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

            Section("Text Polish") {
                Picker(
                    "Mode",
                    selection: Binding(
                        get: { model.selectedTextPolishProfile.id },
                        set: { model.updateTextPolishProfile($0) }
                    )
                ) {
                    ForEach(model.textPolishProfiles) { profile in
                        Text(profilePickerTitle(for: profile))
                            .tag(profile.id)
                            .disabled(!model.isTextPolishProfileSelectable(profile))
                    }
                }

                LabeledContent("Backend", value: model.selectedTextPolishBackendLabel)

                Text(model.selectedTextPolishStatusText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LabeledContent("Apple Intelligence", value: model.appleIntelligenceStatusText)

                if let textPolishSelectionMessage = model.textPolishSelectionMessage {
                    Text(textPolishSelectionMessage)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Prompt")
                        .font(.headline)

                    if model.selectedTextPolishPromptIsEditable {
                        TextEditor(
                            text: Binding(
                                get: { model.selectedTextPolishPrompt },
                                set: { model.updateSelectedTextPolishPrompt($0) }
                            )
                        )
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 150)

                        HStack {
                            Spacer()

                            Button("Reset Prompt") {
                                model.resetSelectedTextPolishPrompt()
                            }
                        }
                    } else {
                        ScrollView {
                            Text(model.selectedTextPolishPrompt)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 120)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }

                Text("Minimal, Technical, Rewrite, and Custom use Apple Intelligence fully on-device and wait for the rewritten result before pasting.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Vocabulary") {
                TextEditor(text: $dictationVocabularyDraft)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .onChange(of: dictationVocabularyDraft) { _, newValue in
                    model.updateDictationVocabularyText(newValue)
                }

                HStack {
                    Text("One word or phrase per line. This is the full speech-recognition vocabulary hint list.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    Button("Reset Vocabulary") {
                        model.resetDictationVocabulary()
                        dictationVocabularyDraft = model.dictationVocabularyText
                    }
                }
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

            Section("Language Model") {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.settings.selectedLanguage.menuTitle)
                        Text(model.selectedLanguageModelStatus.displayText)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if model.selectedLanguageModelStatus.showsRetryAction {
                        Button("Retry") {
                            Task { await model.retrySelectedLanguagePreparation() }
                        }
                        .disabled(!model.selectedLanguageModelStatus.isRetryEnabled)
                    }
                }

                Text("MyWhisper prepares only the currently selected Apple on-device speech model for this app session.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Storage") {
                Text("History is stored locally with unlimited retention until you delete it manually.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear {
            model.refreshTextPolishAvailability()
            dictationVocabularyDraft = model.dictationVocabularyText
        }
    }

    private func profilePickerTitle(for profile: TextPolishProfile) -> String {
        guard !model.isTextPolishProfileSelectable(profile) else {
            return profile.name
        }

        return "\(profile.name) (Unavailable)"
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
