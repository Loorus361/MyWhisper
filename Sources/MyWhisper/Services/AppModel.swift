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
    var audioLevel: Double = 0
    var liveTranscriptPreview: String = ""
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
    private let overlayController: OverlayWindowController

    private var overlayHideTask: Task<Void, Never>?
    private var preparedLanguageIDs = Set<String>()
    private var preparationTask: Task<Bool, Never>?
    private var preparationTaskToken: UUID?
    private var preparingLanguageID: String?
    private var isHotkeyHeld = false

    init() {
        self.settings = settingsStore.load()
        self.history = historyStore.load()
        self.permissionSnapshot = permissionService.snapshot()
        self.textPolishCoordinator = TextPolishCoordinator()
        self.dictationService = DictationService(contextualStrings: AppConstants.defaultContextualStrings)
        self.hotkeyService = HotkeyService(
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: UInt32(controlKey | optionKey)
        )
        self.overlayController = OverlayWindowController()

        dictationService.onAudioLevel = { [weak self] level in
            Task { @MainActor [weak self] in
                self?.audioLevel = level
            }
        }

        dictationService.onLiveTranscript = { [weak self] preview in
            Task { @MainActor [weak self] in
                self?.liveTranscriptPreview = preview
            }
        }

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

        overlayController.bind(to: self)

        do {
            try hotkeyService.register()
        } catch {
            presentError("Failed to register the global hotkey.")
        }

        selectedLanguageModelStatus = preparedLanguageIDs.contains(settings.selectedLanguage.localeIdentifier)
            ? .ready
            : .idle
        reconcileTextPolishSelection(persist: true)
        schedulePreparationIfPossible(for: settings.selectedLanguage)
    }

    var lastRecord: TranscriptionRecord? {
        history.first
    }

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

    var overlayModeLabel: String {
        selectedTextPolishProfile.name
    }

    var overlayStatusText: String {
        switch dictationState {
        case .preparing:
            return preparationStatusText
        case .error(let message):
            return message
        default:
            return dictationState.overlayTitle
        }
    }

    var menuStatusText: String {
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
        default:
            return overlayStatusText
        }
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
        liveTranscriptPreview = ""
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

    func copyLastFinalText() {
        guard let text = lastRecord?.finalText else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
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
        overlayHideTask?.cancel()
        audioLevel = 0
        liveTranscriptPreview = ""
        lastErrorMessage = nil

        if !preparedLanguageIDs.contains(settings.selectedLanguage.localeIdentifier) {
            dictationState = .preparing
            overlayController.show()
            await Task.yield()
        }

        guard await ensureReadyForDictation() else { return }
        guard isHotkeyHeld else {
            dictationState = .idle
            overlayController.hide()
            return
        }

        dictationState = .preparing
        overlayController.show()

        do {
            try await dictationService.startCapture(language: settings.selectedLanguage)

            guard isHotkeyHeld else {
                await dictationService.cancelCapture()
                dictationState = .idle
                overlayController.hide()
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
        audioLevel = 0

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

            liveTranscriptPreview = ""
            dictationState = .inserted
            overlayController.show()
            scheduleOverlayHide(after: AppConstants.insertedOverlayDuration)
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
        audioLevel = 0
        liveTranscriptPreview = ""
        lastErrorMessage = message
        dictationState = .error(message)
        overlayController.show()
        scheduleOverlayHide(after: AppConstants.errorOverlayDuration)
    }

    private func scheduleOverlayHide(after duration: TimeInterval) {
        overlayHideTask?.cancel()
        overlayHideTask = Task { @MainActor [weak self] in
            let delay = UInt64(duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled else { return }
            self.dictationState = .idle
            self.audioLevel = 0
            self.liveTranscriptPreview = ""
            self.overlayController.hide()
        }
    }
}
