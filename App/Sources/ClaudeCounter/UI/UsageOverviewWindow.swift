import AppKit
import SwiftUI

/// Standalone native window showing Claude + Codex usage side by side. Singleton
/// like `UsageWindow`; hosts the SwiftUI `UsageOverviewView` via
/// `NSHostingController` and persists its position between launches.
@MainActor
final class UsageOverviewWindow {
    static let shared = UsageOverviewWindow()

    private var window: NSWindow?

    private init() {}

    func show(appState: AppState) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Usage — Claude + Codex"
        win.isReleasedWhenClosed = false
        win.center()
        win.setFrameAutosaveName("ClaudeCounter.UsageOverviewWindow")
        win.contentViewController = NSHostingController(
            rootView: UsageOverviewView(appState: appState)
        )
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}
