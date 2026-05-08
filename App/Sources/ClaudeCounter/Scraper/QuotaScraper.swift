import Foundation
import WebKit

/// Hidden WKWebView that loads claude.ai/settings/usage every minute,
/// extracts current/weekly % via JS, and pushes to AppState.
@MainActor
final class QuotaScraper: NSObject {
    static let usageURL = URL(string: "https://claude.ai/settings/usage")!
    static let interval: TimeInterval = 60
    static let maxRetries = 2

    private weak var appState: AppState?
    var webView: WKWebView?
    var timer: Timer?
    var isLoading = false
    var retryCount = 0

    func start(appState: AppState) {
        self.appState = appState
        let wv = WebViewFactory.make()
        wv.navigationDelegate = self
        wv.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        webView = wv
        scrape()
        timer = Timer.scheduledTimer(
            withTimeInterval: Self.interval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.scrape() }
        }
    }

    func scrape() {
        guard !isLoading else { return }
        isLoading = true
        retryCount = 0
        webView?.load(URLRequest(url: Self.usageURL))
    }

    func appStateRef() -> AppState? { appState }
}
