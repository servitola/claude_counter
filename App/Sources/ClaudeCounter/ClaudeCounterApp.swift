import AppKit

// MARK: - Main

@main
enum Main {
    static func main() {
        // Headless one-shot: `ClaudeCounter --json` prints usage JSON and exits
        // before any menu-bar UI is created. Pull-only, no disk writes.
        if CommandLine.arguments.dropFirst().contains(StatusCLI.flag) {
            StatusCLI.run()
        }
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
    private let codexPoller = CodexPoller()
    private let settingsStore = SettingsStore()
    // Held strongly for the app's lifetime; the NSStatusItem inside
    // disappears from the menu bar the moment its owner is released.
    // periphery:ignore
    private var statusBar: StatusBarController?
    /// Hosts the `--json` IPC responder for the app's lifetime; releasing it
    /// unregisters the Mach port.
    private var statusServer: StatusServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Compile content blocker before any WebView is built. Async,
        // takes ~50-200ms — first scrape may run before it's ready,
        // every subsequent one is blocked.
        ContentBlocker.shared.prewarm()
        // Evict WebKit's HTTP resource cache (disk + memory) on every
        // launch. claude.ai's content-hashed bundles otherwise accumulate
        // in the shared .default() store unbounded (700 MB+ observed).
        // Async, cookies/localStorage untouched, so login survives.
        WebViewFactory.purgeResourceCache()
        // Restore the persisted provider display choice + title format before
        // the status bar renders its first title.
        appState.displayMode = settingsStore.displayMode()
        appState.titleFormat = settingsStore.titleFormat()
        statusBar = StatusBarController(
            appState: appState,
            scraper: scraper,
            codexPoller: codexPoller,
            settingsStore: settingsStore
        )
        // Expose the current snapshot to `ClaudeCounter --json` over a local
        // Mach port. Pull-only, no port, no disk.
        statusServer = StatusServer(appState: appState)
        statusServer?.start()
        scraper.start(appState: appState)
        codexPoller.start(appState: appState)
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    )
        -> Bool
    {
        false
    }
}
