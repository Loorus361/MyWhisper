// Declares the menu bar extra, history window, and settings window for MyWhisper.
import AppKit
import MyWhisperCore
import SwiftUI

@main
struct MyWhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MyWhisperRootScenes()
    }
}
