import AppKit

// MARK: - Main

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // LSUIElement=true in Info.plist keeps Dock icon hidden, but we
        // still want windows to take focus when explicitly opened.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private let scraper = QuotaScraper()
    // Held strongly for the app's lifetime; the NSStatusItem inside
    // disappears from the menu bar the moment its owner is released.
    // periphery:ignore
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Compile content blocker before any WebView is built. Async,
        // takes ~50-200ms — first scrape may run before it's ready,
        // every subsequent one is blocked.
        ContentBlocker.shared.prewarm()
        statusBar = StatusBarController(
            appState: appState, scraper: scraper
        )
        scraper.start(appState: appState)
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    )
        -> Bool
    {
        false
    }
}
