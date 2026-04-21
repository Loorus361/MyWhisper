// Defines the app scenes shared by the executable target and Xcode previews.
import SwiftUI

public struct MyWhisperScenes: Scene {
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
