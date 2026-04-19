// Owns the floating overlay panel that shows dictation status above the desktop.
import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let panel: NSPanel

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 98),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
    }

    func bind(to model: AppModel) {
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
    }

    func show() {
        updateFrame()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func updateFrame() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let size = NSSize(width: 320, height: 98)
        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.midX - size.width / 2
        let y = visibleFrame.maxY - size.height - 16

        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
    }
}
