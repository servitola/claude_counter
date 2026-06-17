import AppKit
import Foundation
import WebKit

/// API-first usage poller. On each 60 s tick `scrape()` calls the JSON API
/// (`UsageAPIClient`) FIRST; on success it pushes the parsed snapshot to
/// `AppState` WITHOUT building a `WKWebView` — that is the memory win (no
/// per-tick WebContent/GPU/Networking helper spawn).
///
/// The ephemeral-WebView DOM-scrape pipeline is RETAINED, demoted to a
/// fallback (`runWebViewFallback()`) that only runs when the API path cannot
/// answer (`.needsCookieRefresh` / `.decodeFailed`). The WebView is still
/// ephemeral: created at the start of a fallback, torn down at the end
/// (cookies persist in shared `WKWebsiteDataStore.default()`).
///
/// Decision 7 backoff: a `.notLoggedIn` result sets `loggedOut`, which
/// suppresses the WebView fallback on subsequent ticks (no login-WebView spam,
/// preserves US-5 quiet-when-logged-out). The flag PERSISTS across automatic
/// 60 s ticks — the plain `scrape()` the `Timer` calls never clears it, so a
/// logged-out + expired-cookie state can't relaunch the login WebView every
/// minute. It is cleared only by `forceRefresh()` (wired to the three explicit
/// triggers — system wake, "Refresh Now", usage-window open) or automatically
/// by a `.success` result (user is clearly authed again).
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

    // MARK: - Decision 7 backoff + concurrency guards

    /// Set by a `.notLoggedIn` API result (or by `/login` detection on the
    /// fallback path). While set, `runWebViewFallback()` returns immediately
    /// without building a WebView, so no login-WebView is spawned tick after
    /// tick. PERSISTS across automatic ticks; cleared only by `forceRefresh()`
    /// (explicit re-probe) or a `.success` result.
    var loggedOut = false
    /// Single-flight guard: only one orchestrator pass is in flight at a time,
    /// so overlapping timer/wake/Refresh/window-open triggers don't stack.
    /// Internal (not `private`) so the orchestrator extension can read it.
    var isFetchingNow = false
    /// The in-flight orchestrator Task, exposed only so tests can await it.
    var inFlightTask: Task<Void, Never>?

    // MARK: - Injected seams

    /// The API probe. Defaults to the production `UsageAPIClient.fetch()`;
    /// tests substitute a scripted `UsageFetchResult` with no network.
    /// Internal (not `private`) so the orchestrator extension can call it.
    let fetchUsage: @Sendable () async -> UsageFetchResult
    /// Test override for the WebView fallback body. When `nil`, the real
    /// ephemeral-WebView pipeline (`buildEphemeralWebView()`) runs; tests
    /// substitute a closure that counts entries and simulates a DOM-scrape
    /// success. Internal so the orchestrator extension can read it.
    let runFallbackOverride: (@MainActor () -> Void)?

    /// - Parameters:
    ///   - fetchUsage: API probe seam (default: production `UsageAPIClient`).
    ///   - runFallback: WebView fallback body seam (default: real pipeline).
    init(
        fetchUsage: (@Sendable () async -> UsageFetchResult)? = nil,
        runFallback: (@MainActor () -> Void)? = nil
    ) {
        self.fetchUsage = fetchUsage ?? Self.makeProductionFetch()
        self.runFallbackOverride = runFallback
        super.init()
    }

    // MARK: - Lifecycle

    /// Wire `AppState` without starting the timer (used by `start` and tests).
    func attach(appState: AppState) {
        self.appState = appState
    }

    func start(appState: AppState) {
        attach(appState: appState)
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
    /// user returns. `forceRefresh()` clears the Decision-7 backoff so a
    /// logged-out state is re-probed (and the WebView fallback re-enabled).
    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                AppLog.scraper.notice("System wake — forcing scrape")
                self?.forceRefresh()
            }
        }
    }

    func appStateRef() -> AppState? {
        appState
    }
}
