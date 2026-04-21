// Collects app-wide constants for identifiers and runtime timings.
import AVFoundation
import Foundation
import SwiftUI

enum AppConstants {
    static let appName = "MyWhisper"
    static let bundleIdentifier = "com.carlosanderssohn.MyWhisper"
    static let historyWindowID = "history"
    static let settingsWindowID = "settings"
    static let insertedOverlayDuration: TimeInterval = 1.0
    static let errorOverlayDuration: TimeInterval = 2.0
    static let sessionGap: TimeInterval = 5 * 60
    static let clipboardRestoreDelay: UInt64 = 350_000_000
    static let audioTapBufferSize: AVAudioFrameCount = 4096
}

public struct MyWhisperRootScenes: Scene {
    @State private var model = AppModel()

    public init() {}

    public var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: model.dictationState.menuBarSymbolName)
                Text(model.settings.selectedLanguage.shortCode)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .accessibilityLabel("MyWhisper \(model.settings.selectedLanguage.shortCode)")
        }
        .menuBarExtraStyle(.menu)

        Window("History", id: AppConstants.historyWindowID) {
            HistoryWindowView(model: model)
                .background(AppWindowPlacementView(role: .history))
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1040, height: 680)

        Settings {
            SettingsView(model: model)
                .frame(minWidth: 580, minHeight: 700)
                .background(AppWindowPlacementView(role: .settings))
        }
    }
}
