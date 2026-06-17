import Foundation
import WebKit

// MARK: - API-first orchestration (Task 6)

extension QuotaScraper {
    /// One automatic tick of the poller. API-first: probe the JSON API off-main,
    /// then apply the classified result on MainActor. This is the path the 60 s
    /// `Timer` and the `handleFailure()` retry take, so it must NOT clear the
    /// Decision-7 `loggedOut` backoff — clearing it every tick would defeat the
    /// suppression and re-spin the WebView fallback while logged out. The cheap
    /// HTTP probe still runs each tick (no WebView), so a re-login is noticed
    /// via a later `.success`.
    ///
    /// Synchronous entry (launches a Task internally) so the existing automatic
    /// callers keep compiling unchanged.
    func scrape() {
        // Single-flight: overlapping triggers become no-ops until the in-flight
        // fetch resolves.
        guard !isFetchingNow else { return }
        isFetchingNow = true

        inFlightTask = Task { [weak self] in
            let result = await self?.fetchUsage()
            await MainActor.run {
                guard let self else { return }
                self.isFetchingNow = false
                if let result { self.apply(result) }
            }
        }
    }

    /// The single explicit re-probe entry point. Clears the Decision-7
    /// `loggedOut` backoff, then runs a normal `scrape()`. Wired to the three
    /// explicit user/system triggers — system wake (`observeWake()`), "Refresh
    /// Now" (`refresh()`), and usage-window open (`openWindow()`) — so a fresh
    /// full attempt (including the WebView fallback) becomes possible again.
    /// The automatic `Timer` deliberately does NOT route through here.
    func forceRefresh() {
        loggedOut = false
        scrape()
    }

    /// Apply a classified API result on MainActor.
    private func apply(_ result: UsageFetchResult) {
        switch result {
        case .success(let usage):
            // Normal tick: push to AppState, NO WebView. A success means the
            // user is clearly authed again, so clear the Decision-7 backoff
            // (this is the only automatic path that clears it — a re-login is
            // noticed even without an explicit re-probe). Reset the fallback
            // retry counter.
            appStateRef()?.usage = usage
            loggedOut = false
            retryCount = 0
            AppLog.scraper.debug("api result=success")

        case .needsCookieRefresh:
            AppLog.scraper.notice("api result=needsCookieRefresh — webview fallback")
            runWebViewFallback()

        case .decodeFailed:
            AppLog.scraper.notice("api result=decodeFailed — webview fallback")
            runWebViewFallback()

        case .notLoggedIn:
            // Decision 7 backoff: suppress the WebView fallback next tick.
            loggedOut = true
            AppLog.scraper.notice("api result=notLoggedIn — backing off (no webview)")

        case .transport:
            // Transient miss: leave AppState untouched, retry next tick, never
            // enter the WebView path. Value-free (Decision 6).
            AppLog.scraper.notice("api result=transport — leaving state, retry next tick")
        }
    }

    /// The ephemeral-WebView DOM-scrape fallback (last resort). Suppressed by
    /// the Decision-7 backoff: if `loggedOut` is set, return without building a
    /// WebView. Otherwise run the configured fallback body (the real pipeline
    /// in production; a counting/simulating stub in tests).
    func runWebViewFallback() {
        guard !loggedOut else {
            AppLog.scraper.notice("webview fallback suppressed — logged out")
            return
        }
        if let runFallbackOverride {
            runFallbackOverride()
        } else {
            buildEphemeralWebView()
        }
    }

    /// The real ephemeral-WebView body: build via `WebViewFactory`, wire the
    /// navigation delegate, load `usageURL`, arm the watchdog. Behaviorally
    /// identical to the pre-Task-6 `scrape()` body. Guarded so a healthy
    /// in-flight WebView is never replaced mid-scrape.
    func buildEphemeralWebView() {
        guard webView == nil else { return }
        extractAttempts = 0
        let webView = WebViewFactory.make(blockHeavy: true)
        webView.navigationDelegate = self
        webView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        self.webView = webView
        webView.load(URLRequest(url: Self.usageURL))
        armWatchdog()
    }

    /// Production API seam: a fresh `UsageAPIClient` wired with the production
    /// `OrgIDStore`, `CookieBridge` (via `CookieSource.bridged`), and
    /// `UsageMapper` (inside the client). Built on MainActor because
    /// `CookieSource.bridged` touches WebKit; the returned closure captures the
    /// value-typed client and calls `fetch()` off-main.
    static func makeProductionFetch() -> @Sendable () async -> UsageFetchResult {
        let client = UsageAPIClient(cookies: CookieSource.bridged())
        return { await client.fetch() }
    }

    /// Test hook: await the in-flight orchestrator pass (and the MainActor
    /// apply) so an `async` test can assert the observable end state.
    func awaitInFlight() async {
        await inFlightTask?.value
    }
}
