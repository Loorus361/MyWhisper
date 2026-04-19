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
    var lastErrorMessage: String?

    let hotkeyDisplay = "Control + Option + S"
    let activeProfileName = "Standard"

    private let settingsStore = AppSettingsStore()
    private let historyStore = HistoryStore()
    private let permissionService = PermissionService()
    private let pasteService = ClipboardPasteService()
    private let dictationService: DictationService
    private let hotkeyService: HotkeyService
    private let overlayController: OverlayWindowController

    private var overlayHideTask: Task<Void, Never>?
    private var warmedLanguageIDs = Set<String>()
    private var warmUpTask: Task<Void, Never>?
    private var warmingLanguageID: String?
    private var isHotkeyHeld = false

    init() {
        self.settings = settingsStore.load()
        self.history = historyStore.load()
        self.permissionSnapshot = permissionService.snapshot()
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

        scheduleWarmUpIfPossible(for: settings.selectedLanguage)
    }

    var lastRecord: TranscriptionRecord? {
        history.first
    }

    var overlayModeLabel: String {
        activeProfileName
    }

    var overlayStatusText: String {
        switch dictationState {
        case .error(let message):
            return message
        default:
            return dictationState.overlayTitle
        }
    }

    var historyGroups: [HistoryDayGroup] {
        HistoryGrouper.makeDayGroups(from: history)
    }

    func updateLanguage(_ language: AppLanguage) {
        settings.selectedLanguage = language
        settingsStore.save(settings)
        scheduleWarmUpIfPossible(for: language)
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
        scheduleWarmUpIfPossible(for: settings.selectedLanguage)
    }

    func requestSpeechPermission() async {
        _ = await permissionService.requestSpeechPermission()
        refreshPermissions()
        scheduleWarmUpIfPossible(for: settings.selectedLanguage)
    }

    func requestAccessibilityPermission() {
        permissionService.promptForAccessibilityPermission()
        refreshPermissions()
    }

    private func refreshPermissions() {
        permissionSnapshot = permissionService.snapshot()
    }

    private func handleHotkeyPressed() async {
        guard dictationState == .idle else { return }
        isHotkeyHeld = true

        if !warmedLanguageIDs.contains(settings.selectedLanguage.localeIdentifier) {
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

        overlayHideTask?.cancel()
        audioLevel = 0
        lastErrorMessage = nil
        dictationState = .listening
        overlayController.show()

        do {
            try dictationService.startCapture(language: settings.selectedLanguage)
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
            let finalText = TextPolisher.polish(rawText, language: settings.selectedLanguage)

            try pasteService.paste(finalText)

            let record = TranscriptionRecord(
                language: settings.selectedLanguage,
                rawText: rawText,
                finalText: finalText
            )

            history.insert(record, at: 0)
            historyStore.save(history)

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

        await warmUpSelectedLanguageIfNeeded()

        return true
    }

    private func scheduleWarmUpIfPossible(for language: AppLanguage) {
        guard permissionService.microphonePermission() == .granted else { return }
        guard permissionService.speechPermission() == .granted else { return }
        guard !warmedLanguageIDs.contains(language.localeIdentifier) else { return }
        guard warmingLanguageID != language.localeIdentifier else { return }

        warmUpTask?.cancel()
        warmingLanguageID = language.localeIdentifier
        warmUpTask = makeWarmUpTask(for: language)
    }

    private func warmUpSelectedLanguageIfNeeded() async {
        let language = settings.selectedLanguage

        guard !warmedLanguageIDs.contains(language.localeIdentifier) else { return }

        if warmingLanguageID == language.localeIdentifier, let warmUpTask {
            await warmUpTask.value
            return
        }

        warmingLanguageID = language.localeIdentifier
        let task = makeWarmUpTask(for: language)
        warmUpTask = task
        await task.value
    }

    private func makeWarmUpTask(for language: AppLanguage) -> Task<Void, Never> {
        let localeIdentifier = language.localeIdentifier

        return Task { @MainActor [weak self] in
            guard let self else { return }

            defer {
                if self.warmingLanguageID == localeIdentifier {
                    self.warmingLanguageID = nil
                }
                if self.warmUpTask?.isCancelled == false, self.warmedLanguageIDs.contains(localeIdentifier) {
                    self.warmUpTask = nil
                } else if self.warmingLanguageID == nil {
                    self.warmUpTask = nil
                }
            }

            do {
                try await self.dictationService.warmUp(language: language)
                self.warmedLanguageIDs.insert(localeIdentifier)
            } catch {
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func presentError(_ message: String) {
        audioLevel = 0
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
            self.overlayController.hide()
        }
    }
}
