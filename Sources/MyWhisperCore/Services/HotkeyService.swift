// Registers and dispatches the global push-to-talk hotkey using Carbon hotkey APIs.
import AppKit
import Carbon.HIToolbox
import Foundation

@MainActor
final class HotkeyService {
    var onPressed: (() -> Void)?
    var onReleased: (() -> Void)?

    private let keyCode: UInt16
    private let requiredModifiers: NSEvent.ModifierFlags

    private var eventHandler: EventHandlerRef?
    private var eventHandlerUPP: EventHandlerUPP?
    private var hotKeyRef: EventHotKeyRef?
    private let hotKeyID = EventHotKeyID(signature: HotkeyService.signature, id: 1)
    /// Guards against duplicate press events and stray releases.
    private var isKeyDown = false

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.requiredModifiers = modifiers
    }

    func register() throws {
        guard hotKeyRef == nil else { return }

        var eventSpecs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handler: EventHandlerUPP = { _, eventRef, userData in
            guard let eventRef, let userData else { return noErr }

            let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
            return service.handleCarbonEvent(eventRef)
        }

        var installedHandler: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            eventSpecs.count,
            &eventSpecs,
            userData,
            &installedHandler
        )

        guard installStatus == noErr, let installedHandler else {
            throw HotkeyError.registrationFailed
        }

        var registeredHotKey: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers(from: requiredModifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredHotKey
        )

        guard registerStatus == noErr, let registeredHotKey else {
            RemoveEventHandler(installedHandler)
            throw HotkeyError.registrationFailed
        }

        eventHandlerUPP = handler
        eventHandler = installedHandler
        hotKeyRef = registeredHotKey
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }

        eventHandlerUPP = nil
        isKeyDown = false
    }

    private func handleCarbonEvent(_ eventRef: EventRef) -> OSStatus {
        var resolvedHotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &resolvedHotKeyID
        )

        guard status == noErr,
              resolvedHotKeyID.id == hotKeyID.id,
              resolvedHotKeyID.signature == hotKeyID.signature
        else {
            return noErr
        }

        switch GetEventKind(eventRef) {
        case UInt32(kEventHotKeyPressed):
            guard !isKeyDown else { return noErr }
            isKeyDown = true
            onPressed?()
        case UInt32(kEventHotKeyReleased):
            guard isKeyDown else { return noErr }
            isKeyDown = false
            onReleased?()
        default:
            break
        }

        return noErr
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0

        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }

        return modifiers
    }

    private static let signature: OSType = 0x4D575350
}

private enum HotkeyError: LocalizedError {
    case registrationFailed

    var errorDescription: String? {
        "The global hotkey could not be registered. Another app may already be using it, or Accessibility access may still be missing."
    }
}
