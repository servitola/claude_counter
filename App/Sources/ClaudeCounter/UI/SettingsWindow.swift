import AppKit
import SwiftUI

/// Standalone settings window (provider display-mode picker). Singleton like
/// `UsageWindow`; hosts the SwiftUI `SettingsView` via `NSHostingController`.
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()

    private var window: NSWindow?

    private init() {}

    func show(appState: AppState, store: SettingsStore) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Settings"
        win.isReleasedWhenClosed = false
        win.center()
        win.setFrameAutosaveName("ClaudeCounter.SettingsWindow")
        win.contentViewController = NSHostingController(
            rootView: SettingsView(appState: appState, store: store)
        )
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}
