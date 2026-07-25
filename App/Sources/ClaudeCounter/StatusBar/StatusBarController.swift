import AppKit
import Observation

/// Owns the NSStatusItem in the menu bar.
/// Click → menu (Open Usage / Launch at Login / Refresh / Quit).
/// Title auto-updates whenever AppState.usage changes.
@MainActor
final class StatusBarController: NSObject {
    let appState: AppState
    let scraper: QuotaScraper
    let codexPoller: CodexPoller
    let settingsStore: SettingsStore
    let statusItem: NSStatusItem
    var refreshTimer: Timer?

    init(
        appState: AppState,
        scraper: QuotaScraper,
        codexPoller: CodexPoller,
        settingsStore: SettingsStore
    ) {
        self.appState = appState
        self.scraper = scraper
        self.codexPoller = codexPoller
        self.settingsStore = settingsStore
        self.statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        super.init()
        statusItem.menu = makeMenu()
        observe()
        startRefreshTimer()
    }

    /// Render the strip for the current provider selection. Reads `usage`,
    /// `codex`, `displayMode`, and `titleFormat` so `withObservationTracking`
    /// re-fires on any of them.
    func renderTitle() {
        statusItem.button?.attributedTitle = QuotaTitleFormatter.render(
            claude: appState.usage,
            codex: appState.codex,
            mode: appState.displayMode,
            format: appState.titleFormat
        )
    }

    private func observe() {
        withObservationTracking {
            renderTitle()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    /// Re-render every 60s so reset countdown ticks down without a new scrape.
    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: 60, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.renderTitle()
            }
        }
        // Coalesce with other system timers; a few seconds of drift is fine
        // for a countdown display that only changes minute-by-minute.
        refreshTimer?.tolerance = 10
    }
}
