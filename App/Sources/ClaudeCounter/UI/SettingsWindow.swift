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
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 700),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Settings"
        win.isReleasedWhenClosed = false
        win.applyGlassChrome(
            content: SettingsView(appState: appState, store: store),
            sizesToContent: false
        )
        win.center()
        // v2: 1.1.0 saved screen-tall frames while the window sized to its content.
        win.setFrameAutosaveName("ClaudeCounter.SettingsWindow.v2")
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}
