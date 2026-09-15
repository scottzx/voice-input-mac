import AppKit
import SwiftUI
import VoiceInputCore

@main
struct VoiceInputMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(state)
        } label: {
            Image(systemName: state.menuIcon)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hud: HUDController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppState.shared.bootstrap()
        hud = HUDController(state: AppState.shared)
        hud?.start()
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let window = note.object as? NSWindow else { return }
            let typeName = String(describing: type(of: window))
            let looksLikeSettings = window.title.contains("设置")
                || window.title.contains("Settings")
                || typeName.contains("Settings")
                || typeName.contains("Preferences")
            if looksLikeSettings {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.stopListening()
    }
}
