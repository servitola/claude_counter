import AppKit
import Observation

/// Owns the NSStatusItem in the menu bar.
/// Click → menu (Open Usage / Launch at Login / Refresh / Quit).
/// Title auto-updates whenever AppState.usage changes.
@MainActor
final class StatusBarController: NSObject {
    let appState: AppState
    let scraper: QuotaScraper
    let statusItem: NSStatusItem
    var refreshTimer: Timer?

    init(appState: AppState, scraper: QuotaScraper) {
        self.appState = appState
        self.scraper = scraper
        self.statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        super.init()
        statusItem.menu = makeMenu()
        observe()
        startRefreshTimer()
    }

    private func observe() {
        withObservationTracking {
            statusItem.button?.attributedTitle =
                QuotaTitleFormatter.render(appState.usage)
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
                guard let self else { return }
                self.statusItem.button?.attributedTitle =
                    QuotaTitleFormatter.render(self.appState.usage)
            }
        }
        // Coalesce with other system timers; a few seconds of drift is fine
        // for a countdown display that only changes minute-by-minute.
        refreshTimer?.tolerance = 10
    }
}
