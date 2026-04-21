// Positions user-facing app windows near the macOS menu bar and brings them forward.
import AppKit
import SwiftUI

enum AppWindowRole {
    case history
    case settings

    var identifier: String {
        switch self {
        case .history:
            AppConstants.historyWindowID
        case .settings:
            AppConstants.settingsWindowID
        }
    }
}

@MainActor
enum AppWindowPositioner {
    static func prepare(_ window: NSWindow, for role: AppWindowRole) {
        window.identifier = NSUserInterfaceItemIdentifier(role.identifier)
        placeNearMenuBar(window)
        bringForward(window)
    }

    static func bringForward(role: AppWindowRole) {
        DispatchQueue.main.async {
            bringForwardIfFound(role: role)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            bringForwardIfFound(role: role)
        }
    }

    private static func bringForwardIfFound(role: AppWindowRole) {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == role.identifier }) else {
            return
        }

        placeNearMenuBar(window)
        bringForward(window)
    }

    private static func placeNearMenuBar(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let frame = window.frame
        let visibleFrame = screen.visibleFrame
        let padding: CGFloat = 16
        let x = clamped(
            visibleFrame.midX - frame.width / 2,
            minimum: visibleFrame.minX + padding,
            maximum: visibleFrame.maxX - frame.width - padding
        )
        let y = clamped(
            visibleFrame.maxY - frame.height - padding,
            minimum: visibleFrame.minY + padding,
            maximum: visibleFrame.maxY - frame.height - padding
        )

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private static func bringForward(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private static func clamped(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        guard minimum <= maximum else {
            return minimum
        }

        return min(max(value, minimum), maximum)
    }
}

struct AppWindowPlacementView: NSViewRepresentable {
    let role: AppWindowRole

    func makeNSView(context: Context) -> PlacementProbeView {
        PlacementProbeView(role: role)
    }

    func updateNSView(_ nsView: PlacementProbeView, context: Context) {
        nsView.role = role
    }
}

final class PlacementProbeView: NSView {
    var role: AppWindowRole

    init(role: AppWindowRole) {
        self.role = role
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard let window else {
            return
        }

        DispatchQueue.main.async {
            AppWindowPositioner.prepare(window, for: self.role)
        }
    }
}
