// Coordinates hotkeys, permissions, dictation, paste insertion, overlay state, and persistence.
import AppKit
import Carbon.HIToolbox
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var settings: AppSettings
    var history: [TranscriptionRecord]
    var permissionSnapshot: PermissionSnapshot
    var dictationState: DictationState = .idle
    var selectedLanguageModelStatus: LanguageModelStatus = .idle
    var lastErrorMessage: String?
    var textPolishSelectionMessage: String?

    let hotkeyDisplay = "Control + Option + S"

    private let settingsStore = AppSettingsStore()
    private let historyStore = HistoryStore()
    private let permissionService = PermissionService()
    private let pasteService = ClipboardPasteService()
    private let textPolishCoordinator: any TextPolishCoordinating
    private let dictationService: DictationService
    private let hotkeyService: HotkeyService

    private var stateResetTask: Task<Void, Never>?
    private var insertionFeedbackTask: Task<Void, Never>?
    private var preparedLanguageIDs = Set<String>()
    private var preparationTask: Task<Bool, Never>?
    private var preparationTaskToken: UUID?
    private var preparingLanguageID: String?
    private var isHotkeyHeld = false
    private var showsInsertionFeedback = false

    init() {
        self.settings = settingsStore.load()
        self.history = historyStore.load()
        self.permissionSnapshot = permissionService.snapshot()
        self.textPolishCoordinator = TextPolishCoordinator()
        self.dictationService = DictationService()
        self.hotkeyService = HotkeyService(
            keyCode: UInt16(kVK_ANSI_S),
            modifiers: [.control, .option]
        )
        dictationService.onLanguageModelStatus = { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.selectedLanguageModelStatus = status

                if case .failed(let message) = status {
                    self.lastErrorMessage = message
                }
            }
        }

        hotkeyService.onPressed = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleHotkeyPressed()
            }
        }

        hotkeyService.onReleased = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleHotkeyReleased()
            }
        }

        do {
            try hotkeyService.register()
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        selectedLanguageModelStatus = preparedLanguageIDs.contains(settings.selectedLanguage.localeIdentifier)
            ? .ready
            : .idle
        reconcileTextPolishSelection(persist: true)
        schedulePreparationIfPossible(for: settings.selectedLanguage)
    }

#if DEBUG
    static func preview(
        settings: AppSettings = .preview,
        history: [TranscriptionRecord] = TranscriptionRecord.previewRecords,
        permissionSnapshot: PermissionSnapshot = .previewGranted,
        dictationState: DictationState = .idle,
        selectedLanguageModelStatus: LanguageModelStatus = .ready,
        lastErrorMessage: String? = nil,
        textPolishSelectionMessage: String? = nil
    ) -> AppModel {
        AppModel(
            previewSettings: settings,
            history: history,
            permissionSnapshot: permissionSnapshot,
            dictationState: dictationState,
            selectedLanguageModelStatus: selectedLanguageModelStatus,
            lastErrorMessage: lastErrorMessage,
            textPolishSelectionMessage: textPolishSelectionMessage
        )
    }

    private init(
        previewSettings settings: AppSettings,
        history: [TranscriptionRecord],
        permissionSnapshot: PermissionSnapshot,
        dictationState: DictationState,
        selectedLanguageModelStatus: LanguageModelStatus,
        lastErrorMessage: String?,
        textPolishSelectionMessage: String?
    ) {
        self.settings = settings
        self.history = history
        self.permissionSnapshot = permissionSnapshot
        self.dictationState = dictationState
        self.selectedLanguageModelStatus = selectedLanguageModelStatus
        self.lastErrorMessage = lastErrorMessage
        self.textPolishSelectionMessage = textPolishSelectionMessage
        self.textPolishCoordinator = PreviewTextPolishCoordinator()
        self.dictationService = DictationService()
        self.hotkeyService = HotkeyService(
            keyCode: UInt16(kVK_ANSI_S),
            modifiers: [.control, .option]
        )
    }
#endif

    var textPolishProfiles: [TextPolishProfile] {
        settings.textPolishProfiles
    }

    var selectedTextPolishProfile: TextPolishProfile {
        settings.selectedTextPolishProfile
    }

    var activeProfileName: String {
        selectedTextPolishProfile.name
    }

    var selectedTextPolishBackendLabel: String {
        selectedTextPolishProfile.backend.displayName
    }

    var selectedTextPolishStatusText: String {
        switch selectedTextPolishProfile.backend {
        case .deterministic:
            return "Fast local cleanup with simple filler-word removal and punctuation."
        case .appleIntelligence:
            return appleIntelligenceStatusText
        }
    }

    var appleIntelligenceStatus: AppleIntelligenceStatus {
        textPolishCoordinator.appleIntelligenceStatus(for: settings.selectedLanguage)
    }

    var appleIntelligenceStatusText: String {
        appleIntelligenceStatus.displayText(for: settings.selectedLanguage)
    }

    var selectedTextPolishPrompt: String {
        selectedTextPolishProfile.prompt
    }

    var selectedTextPolishPromptIsEditable: Bool {
        selectedTextPolishProfile.isPromptEditable
    }

    var dictationVocabularyText: String {
        settings.dictationVocabulary.joined(separator: "\n")
    }

    var menuStatusText: String {
        if showsInsertionFeedback, dictationState == .idle {
            return "Inserted."
        }

        switch dictationState {
        case .idle:
            switch selectedLanguageModelStatus {
            case .checking, .downloading, .failed:
                return selectedLanguageModelStatus.displayText
            case .idle, .ready:
                return "Ready"
            }
        case .preparing:
            return preparationStatusText
        case .listening:
            return "Listening\u{2026}"
        case .processing:
            return "Polishing\u{2026}"
        case .inserted:
            return "Inserted."
        case .error(let message):
            return message
        }
    }

    var menuBarSymbolName: String {
        if showsInsertionFeedback, dictationState == .idle {
            return DictationState.inserted.menuBarSymbolName
        }

        return dictationState.menuBarSymbolName
    }

    var historyGroups: [HistoryDayGroup] {
        HistoryGrouper.makeDayGroups(from: history)
    }

    func updateLanguage(_ language: AppLanguage) {
        var updatedSettings = settings
        updatedSettings.selectedLanguage = language
        settings = updatedSettings
        textPolishSelectionMessage = nil
        settingsStore.save(settings)
        lastErrorMessage = nil
        selectedLanguageModelStatus = preparedLanguageIDs.contains(language.localeIdentifier) ? .ready : .idle
        reconcileTextPolishSelection(persist: true)
        schedulePreparationIfPossible(for: language)
    }

    func updateTextPolishProfile(_ id: TextPolishProfileID) {
        guard let profile = settings.textPolishProfile(for: id) else { return }

        switch textPolishCoordinator.availability(for: profile, language: settings.selectedLanguage) {
        case .available:
            var updatedSettings = settings
            updatedSettings.selectedTextPolishProfileID = id
            settings = updatedSettings
            textPolishSelectionMessage = nil
            settingsStore.save(settings)
        case .unavailable(let reason):
            textPolishSelectionMessage = AppleIntelligenceStatus.unavailable(reason).fallbackMessage(
                for: profile.name,
                language: settings.selectedLanguage
            )
        }
    }

    func updateSelectedTextPolishPrompt(_ prompt: String) {
        guard selectedTextPolishPromptIsEditable else { return }

        var updatedSettings = settings
        updatedSettings.updatePrompt(prompt, for: selectedTextPolishProfile.id)
        settings = updatedSettings
        settingsStore.save(settings)
    }

    func resetSelectedTextPolishPrompt() {
        guard selectedTextPolishPromptIsEditable else { return }

        var updatedSettings = settings
        updatedSettings.resetPrompt(for: selectedTextPolishProfile.id)
        settings = updatedSettings
        settingsStore.save(settings)
    }

    func updateDictationVocabularyText(_ text: String) {
        var updatedSettings = settings
        updatedSettings.updateDictationVocabulary(text.components(separatedBy: .newlines))
        settings = updatedSettings
        settingsStore.save(settings)
    }

    func resetDictationVocabulary() {
        var updatedSettings = settings
        updatedSettings.resetDictationVocabulary()
        settings = updatedSettings
        settingsStore.save(settings)
    }

    func refreshTextPolishAvailability() {
        reconcileTextPolishSelection(persist: true)
    }

    func isTextPolishProfileSelectable(_ profile: TextPolishProfile) -> Bool {
        switch textPolishCoordinator.availability(for: profile, language: settings.selectedLanguage) {
        case .available:
            return true
        case .unavailable:
            return false
        }
    }

    func retrySelectedLanguagePreparation() async {
        _ = await prepareSelectedLanguageIfNeeded(force: true, interactive: false)
    }

    func requestMicrophonePermission() async {
        _ = await permissionService.requestMicrophonePermission()
        refreshPermissions()
        schedulePreparationIfPossible(for: settings.selectedLanguage)
    }

    func requestSpeechPermission() async {
        _ = await permissionService.requestSpeechPermission()
        refreshPermissions()
        schedulePreparationIfPossible(for: settings.selectedLanguage)
    }

    func requestAccessibilityPermission() {
        permissionService.promptForAccessibilityPermission()
        refreshPermissions()
    }

    private var preparationStatusText: String {
        switch selectedLanguageModelStatus {
        case .checking, .downloading, .failed:
            return selectedLanguageModelStatus.displayText
        case .idle, .ready:
            return "Preparing dictation..."
        }
    }

    private func refreshPermissions() {
        permissionSnapshot = permissionService.snapshot()
    }

    private func reconcileTextPolishSelection(persist: Bool) {
        let resolvedProfileID = textPolishCoordinator.resolvedProfileID(in: settings)
        guard resolvedProfileID != settings.selectedTextPolishProfileID else { return }

        let previousProfile = settings.selectedTextPolishProfile
        let availability = textPolishCoordinator.availability(
            for: previousProfile,
            language: settings.selectedLanguage
        )

        var updatedSettings = settings
        updatedSettings.selectedTextPolishProfileID = resolvedProfileID
        settings = updatedSettings

        if case .unavailable(let reason) = availability {
            textPolishSelectionMessage = AppleIntelligenceStatus.unavailable(reason).fallbackMessage(
                for: previousProfile.name,
                language: settings.selectedLanguage
            )
        } else {
            textPolishSelectionMessage = nil
        }

        if persist {
            settingsStore.save(settings)
        }
    }

    private func handleHotkeyPressed() async {
        guard dictationState == .idle else { return }
        isHotkeyHeld = true
        stateResetTask?.cancel()
        lastErrorMessage = nil

        if !preparedLanguageIDs.contains(settings.selectedLanguage.localeIdentifier) {
            dictationState = .preparing
            await Task.yield()
        }

        guard await ensureReadyForDictation() else { return }
        guard isHotkeyHeld else {
            dictationState = .idle
            return
        }

        dictationState = .preparing

        do {
            try await dictationService.startCapture(
                language: settings.selectedLanguage,
                contextualStrings: settings.dictationVocabulary
            )

            guard isHotkeyHeld else {
                await dictationService.cancelCapture()
                dictationState = .idle
                return
            }

            dictationState = .listening
        } catch {
            presentError(error.localizedDescription)
        }
    }

    private func handleHotkeyReleased() async {
        isHotkeyHeld = false

        if dictationState == .preparing {
            return
        }

        guard dictationState == .listening else { return }

        dictationState = .processing

        do {
            let rawText = try await dictationService.finishCapture()
            let selectedProfile = selectedTextPolishProfile
            let finalText = try await textPolishCoordinator.polish(
                rawText,
                language: settings.selectedLanguage,
                profile: selectedProfile
            )

            try pasteService.paste(finalText)

            let record = TranscriptionRecord(
                language: settings.selectedLanguage,
                profileName: selectedProfile.name,
                rawText: rawText,
                finalText: finalText
            )

            history.insert(record, at: 0)
            do {
                try historyStore.save(history)
            } catch {
                // Paste already succeeded — don't interrupt the inserted flow.
                // HistoryStore logs the failure via OSLog.
            }

            showInsertionFeedback(for: 1.0)
            dictationState = .idle
        } catch {
            presentError(error.localizedDescription)
        }
    }

    private func ensureReadyForDictation() async -> Bool {
        if permissionService.microphonePermission() != .granted {
            let status = await permissionService.requestMicrophonePermission()
            refreshPermissions()
            guard status == .granted else {
                presentError("Microphone access is required.")
                return false
            }
        }

        if permissionService.speechPermission() != .granted {
            let status = await permissionService.requestSpeechPermission()
            refreshPermissions()
            guard status == .granted else {
                presentError("Speech recognition access is required.")
                return false
            }
        }

        if permissionService.accessibilityPermission() != .granted {
            permissionService.promptForAccessibilityPermission()
            refreshPermissions()
            presentError("Enable Accessibility so MyWhisper can paste into other apps.")
            return false
        }

        return await prepareSelectedLanguageIfNeeded(force: false, interactive: true)
    }

    private func schedulePreparationIfPossible(for language: AppLanguage) {
        guard permissionService.microphonePermission() == .granted else {
            if settings.selectedLanguage == language, !preparedLanguageIDs.contains(language.localeIdentifier) {
                selectedLanguageModelStatus = .idle
            }
            return
        }

        guard permissionService.speechPermission() == .granted else {
            if settings.selectedLanguage == language, !preparedLanguageIDs.contains(language.localeIdentifier) {
                selectedLanguageModelStatus = .idle
            }
            return
        }

        let languageID = language.localeIdentifier

        if preparedLanguageIDs.contains(languageID) {
            if settings.selectedLanguage.localeIdentifier == languageID {
                selectedLanguageModelStatus = .ready
            }
            return
        }

        if preparingLanguageID == languageID, let preparationTask {
            _ = preparationTask
            return
        }

        preparationTask?.cancel()
        preparingLanguageID = languageID
        selectedLanguageModelStatus = .checking

        let token = UUID()
        preparationTaskToken = token
        preparationTask = makePreparationTask(
            for: language,
            interactive: false,
            token: token
        )
    }

    private func prepareSelectedLanguageIfNeeded(force: Bool, interactive: Bool) async -> Bool {
        let language = settings.selectedLanguage
        let languageID = language.localeIdentifier

        if !force, preparedLanguageIDs.contains(languageID) {
            selectedLanguageModelStatus = .ready
            return true
        }

        if preparingLanguageID == languageID, let preparationTask {
            return await preparationTask.value
        }

        preparationTask?.cancel()
        preparingLanguageID = languageID
        selectedLanguageModelStatus = .checking

        let token = UUID()
        preparationTaskToken = token
        let task = makePreparationTask(for: language, interactive: interactive, token: token)
        preparationTask = task
        return await task.value
    }

    private func makePreparationTask(
        for language: AppLanguage,
        interactive: Bool,
        token: UUID
    ) -> Task<Bool, Never> {
        let languageID = language.localeIdentifier

        return Task { @MainActor [weak self] in
            guard let self else { return false }

            defer {
                if self.preparingLanguageID == languageID {
                    self.preparingLanguageID = nil
                }

                if self.preparationTaskToken == token {
                    self.preparationTaskToken = nil
                    self.preparationTask = nil
                }
            }

            do {
                try await self.dictationService.prepare(language: language)
                self.preparedLanguageIDs.insert(languageID)

                if self.settings.selectedLanguage.localeIdentifier == languageID {
                    self.selectedLanguageModelStatus = .ready
                    self.lastErrorMessage = nil
                }

                return true
            } catch is CancellationError {
                if self.settings.selectedLanguage.localeIdentifier == languageID,
                   !self.preparedLanguageIDs.contains(languageID) {
                    self.selectedLanguageModelStatus = .idle
                }

                return false
            } catch {
                if self.settings.selectedLanguage.localeIdentifier == languageID {
                    self.lastErrorMessage = error.localizedDescription
                    self.selectedLanguageModelStatus = .failed(error.localizedDescription)

                    if interactive {
                        self.presentError(error.localizedDescription)
                    }
                }

                return false
            }
        }
    }

    private func presentError(_ message: String) {
        insertionFeedbackTask?.cancel()
        showsInsertionFeedback = false
        lastErrorMessage = message
        dictationState = .error(message)
        scheduleStateReset(after: 2.0)
    }

    private func scheduleStateReset(after duration: TimeInterval) {
        stateResetTask?.cancel()
        stateResetTask = Task { @MainActor [weak self] in
            let delay = UInt64(duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled else { return }
            self.dictationState = .idle
        }
    }

    private func showInsertionFeedback(for duration: TimeInterval) {
        insertionFeedbackTask?.cancel()
        showsInsertionFeedback = true
        insertionFeedbackTask = Task { @MainActor [weak self] in
            let delay = UInt64(duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled else { return }
            self.showsInsertionFeedback = false
        }
    }
}

#if DEBUG
private struct PreviewTextPolishCoordinator: TextPolishCoordinating, Sendable {
    func appleIntelligenceStatus(for language: AppLanguage) -> AppleIntelligenceStatus {
        .available
    }

    func availability(for profile: TextPolishProfile, language: AppLanguage) -> AppleIntelligenceStatus {
        .available
    }

    func resolvedProfileID(in settings: AppSettings) -> TextPolishProfileID {
        settings.selectedTextPolishProfileID
    }

    func polish(_ rawText: String, language: AppLanguage, profile: TextPolishProfile) async throws -> String {
        rawText
    }
}

extension AppSettings {
    static let preview = AppSettings(
        selectedLanguage: .german,
        selectedTextPolishProfileID: .technical
    )
}

extension PermissionSnapshot {
    static let previewGranted = PermissionSnapshot(
        microphone: .granted,
        speech: .granted,
        accessibility: .granted
    )
}

extension TranscriptionRecord {
    static let previewRecords = [
        TranscriptionRecord(
            timestamp: Date(timeIntervalSinceReferenceDate: 777_600_000),
            language: .german,
            profileName: "Technical",
            rawText: "öffne bitte die Settings View und prüfe ob die SwiftUI Preview kompiliert",
            finalText: "Öffne bitte die SettingsView und prüfe, ob die SwiftUI Preview kompiliert."
        ),
        TranscriptionRecord(
            timestamp: Date(timeIntervalSinceReferenceDate: 777_596_400),
            language: .englishUS,
            profileName: "Clean",
            rawText: "add a small canvas preview for every view in the project",
            finalText: "Add a small Canvas preview for every view in the project."
        )
    ]
}
#endif
