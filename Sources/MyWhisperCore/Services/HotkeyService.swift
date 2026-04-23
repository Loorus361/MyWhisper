// Registers and dispatches the global push-to-talk hotkey using NSEvent global monitors.
import AppKit
import Foundation

@MainActor
final class HotkeyService {
    var onPressed: (() -> Void)?
    var onReleased: (() -> Void)?

    private let keyCode: UInt16
    private let requiredModifiers: NSEvent.ModifierFlags

    private var downMonitor: Any?
    private var upMonitor: Any?
    /// Guards against key-repeat floods and stray keyUp events from other uses of the same key.
    private var isKeyDown = false

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.requiredModifiers = modifiers
    }

    func register() throws {
        guard downMonitor == nil else { return }

        // Capture value types so the closures don't need to cross actor boundaries.
        let code = keyCode
        let mods = requiredModifiers

        downMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // isARepeat: macOS fires ~30 keyDown/sec while a key is held — ignore repeats.
            guard !event.isARepeat,
                  event.keyCode == code,
                  event.modifierFlags.intersection([.shift, .control, .option, .command]) == mods
            else { return }
            Task { @MainActor [weak self] in
                guard let self, !self.isKeyDown else { return }
                self.isKeyDown = true
                self.onPressed?()
            }
        }

        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard event.keyCode == code else { return }
            Task { @MainActor [weak self] in
                // Only fire if we actually started from a matched keyDown.
                guard let self, self.isKeyDown else { return }
                self.isKeyDown = false
                self.onReleased?()
            }
        }

        guard downMonitor != nil, upMonitor != nil else {
            unregister()
            throw HotkeyError.registrationFailed
        }
    }

    func unregister() {
        if let m = downMonitor { NSEvent.removeMonitor(m); downMonitor = nil }
        if let m = upMonitor { NSEvent.removeMonitor(m); upMonitor = nil }
        isKeyDown = false
    }
}

private enum HotkeyError: LocalizedError {
    case registrationFailed

    var errorDescription: String? {
        "The global hotkey monitor could not be installed. Grant Accessibility access in System Settings \u{203a} Privacy \u{203a} Accessibility."
    }
}
