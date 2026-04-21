// Pastes transcribed text into the focused app by temporarily using and then restoring the clipboard.
import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

@MainActor
final class ClipboardPasteService {
    func paste(_ text: String) throws {
        guard !text.isEmpty else {
            throw PasteError.emptyText
        }

        let pasteboard = NSPasteboard.general
        let snapshot = snapshot(for: pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw PasteError.failedToWritePasteboard
        }

        let injectedChangeCount = pasteboard.changeCount
        try postPasteShortcut()

        Task { @MainActor [snapshot, injectedChangeCount] in
            try? await Task.sleep(nanoseconds: AppConstants.clipboardRestoreDelay)
            let pasteboard = NSPasteboard.general
            guard pasteboard.changeCount == injectedChangeCount else { return }
            self.restore(snapshot, to: pasteboard)
        }
    }

    private func postPasteShortcut() throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw PasteError.failedToPostPasteShortcut
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        guard let keyDown, let keyUp else {
            throw PasteError.failedToPostPasteShortcut
        }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func snapshot(for pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items: [PasteboardItemSnapshot] = pasteboard.pasteboardItems?.map { item in
            var types = [String: Data]()
            for type in item.types {
                if let data = item.data(forType: type) {
                    types[type.rawValue] = data
                }
            }
            return PasteboardItemSnapshot(types: types)
        } ?? []

        return PasteboardSnapshot(items: items)
    }

    private func restore(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        guard !snapshot.items.isEmpty else { return }

        let restoredItems = snapshot.items.map { snapshotItem in
            let item = NSPasteboardItem()
            for (type, data) in snapshotItem.types {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }

        pasteboard.writeObjects(restoredItems)
    }
}

private struct PasteboardSnapshot: Sendable {
    let items: [PasteboardItemSnapshot]
}

private struct PasteboardItemSnapshot: Sendable {
    let types: [String: Data]
}

private enum PasteError: LocalizedError {
    case emptyText
    case failedToWritePasteboard
    case failedToPostPasteShortcut

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "There was no text to paste."
        case .failedToWritePasteboard:
            return "MyWhisper could not write the transcription to the clipboard."
        case .failedToPostPasteShortcut:
            return "MyWhisper could not trigger paste in the focused app."
        }
    }
}
