import Foundation
import WebKit

/// Polls claude.ai/settings/usage every minute and pushes parsed data
/// to AppState. Critically, the WKWebView is **ephemeral**: created at
/// the start of each scrape, torn down at the end. claude.ai is a
/// heavy SPA — keeping it loaded permanently costs ~700MB of WebContent
/// process memory. Cycling the webview drops idle footprint to ~zero
/// (cookies persist in shared WKWebsiteDataStore.default()).
@MainActor
final class QuotaScraper: NSObject {
    static let usageURL = URL(string: "https://claude.ai/settings/usage")!
    static let interval: TimeInterval = 60
    /// If a scrape doesn't finish in this window we kill the webview
    /// and try again on the next tick. Page typically loads in 2-5s.
    static let watchdogTimeout: TimeInterval = 30
    static let maxRetries = 1

    private weak var appState: AppState?
    private var timer: Timer?
    var webView: WKWebView?
    var watchdog: DispatchWorkItem?
    var retryCount = 0

    func start(appState: AppState) {
        self.appState = appState
        scrape()
        timer = Timer.scheduledTimer(
            withTimeInterval: Self.interval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.scrape() }
        }
    }

    func scrape() {
        guard webView == nil else { return }
        let wv = WebViewFactory.make(blockHeavy: true)
        wv.navigationDelegate = self
        wv.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        webView = wv
        wv.load(URLRequest(url: Self.usageURL))
        armWatchdog()
    }

    func appStateRef() -> AppState? { appState }
}
