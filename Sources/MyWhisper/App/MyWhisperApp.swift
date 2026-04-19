// Declares the menu bar extra, history window, and settings window for MyWhisper.
import AppKit
import SwiftUI

@main
struct MyWhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
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
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1040, height: 680)

        Settings {
            SettingsView(model: model)
                .frame(minWidth: 520, minHeight: 440)
        }
    }
}
