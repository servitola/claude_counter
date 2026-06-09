import AppKit
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
    /// `claude.ai/settings/usage` is a constant; force-unwrap inside a
    /// computed property would still trip lint rules. Build once and
    /// `precondition` if Apple ever rejects the literal.
    static let usageURL: URL = {
        guard let url = URL(string: "https://claude.ai/settings/usage") else {
            preconditionFailure("Static URL string is invalid")
        }
        return url
    }()

    static let interval: TimeInterval = 60
    /// If a scrape doesn't finish in this window we kill the webview
    /// and try again on the next tick. Page typically loads in 2-5s.
    static let watchdogTimeout: TimeInterval = 30
    static let maxRetries = 1
    /// Extraction polling. The React tree usually populates within 2-3s
    /// after didFinish; we start at 1s and retry up to 8 times at 1s
    /// intervals. Watchdog still bounds total scrape time.
    static let pollInterval: TimeInterval = 1
    static let maxExtractAttempts = 8

    private weak var appState: AppState?
    private var timer: Timer?
    var webView: WKWebView?
    var watchdog: DispatchWorkItem?
    var retryCount = 0
    var extractAttempts = 0
    // Wake-notification token. Held strongly so the observer survives
    // for the scraper's lifetime; the scraper itself never deallocates.
    // periphery:ignore
    private var wakeObserver: (any NSObjectProtocol)?

    func start(appState: AppState) {
        self.appState = appState
        scrape()
        timer = Timer.scheduledTimer(
            withTimeInterval: Self.interval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.scrape() }
        }
        // Allow 10s leeway so macOS can coalesce this wakeup with other
        // system timers instead of interrupting the CPU exactly on the dot.
        timer?.tolerance = 10
        observeWake()
    }

    /// `Timer` is paused while the system sleeps and may take a full
    /// interval to fire after wake — long enough that the displayed
    /// usage looks stale. Subscribe to `didWakeNotification` and force
    /// an immediate scrape so the menu-bar refreshes the moment the
    /// user returns.
    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                AppLog.scraper.notice("System wake — forcing scrape")
                self?.scrape()
            }
        }
    }

    func scrape() {
        guard webView == nil else { return }
        extractAttempts = 0
        let webView = WebViewFactory.make(blockHeavy: true)
        webView.navigationDelegate = self
        webView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        self.webView = webView
        webView.load(URLRequest(url: Self.usageURL))
        armWatchdog()
    }

    func appStateRef() -> AppState? {
        appState
    }
}
