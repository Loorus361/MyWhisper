// Registers and dispatches the global push-to-talk hotkey through Carbon event APIs.
import Carbon
import Foundation

final class HotkeyService {
    var onPressed: (() -> Void)?
    var onReleased: (() -> Void)?

    private let keyCode: UInt32
    private let modifiers: UInt32
    private let hotKeyID = EventHotKeyID(signature: 0x4D575350, id: 1)

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    func register() throws {
        guard hotKeyRef == nil else { return }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard
                let eventRef,
                let userData
            else {
                return noErr
            }

            let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()

            GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard hotKeyID.id == service.hotKeyID.id else {
                return noErr
            }

            switch GetEventKind(eventRef) {
            case UInt32(kEventHotKeyPressed):
                service.onPressed?()
            case UInt32(kEventHotKeyReleased):
                service.onReleased?()
            default:
                break
            }

            return noErr
        }

        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            throw HotkeyError.installFailed
        }

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            unregister()
            throw HotkeyError.registrationFailed
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}

private enum HotkeyError: LocalizedError {
    case installFailed
    case registrationFailed

    var errorDescription: String? {
        switch self {
        case .installFailed:
            return "The system hotkey event handler could not be installed."
        case .registrationFailed:
            return "The global hotkey could not be registered."
        }
    }
}
