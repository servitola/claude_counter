import Foundation
import Testing
import WebKit
@testable import ClaudeCounter

// MARK: - QuotaScraperBackoffTests

/// Decision 7 logged-out backoff (review round 1). The `loggedOut` flag must
/// PERSIST across automatic 60 s ticks so a logged-out + expired-cookie state
/// can't relaunch the login WebView every minute; it is cleared only by an
/// explicit `forceRefresh()` re-probe or by a `.success` result. Shared
/// seams/fixtures live in `QuotaScraperTestSupport`.
@MainActor
struct QuotaScraperBackoffTests {
    private typealias Support = QuotaScraperTestSupport

    /// GAP 1 — suppression genuinely fires. After a `.notLoggedIn` pass arms
    /// the backoff, an automatic tick that returns `.needsCookieRefresh` must
    /// NOT enter the WebView fallback. Litmus: removing the `guard !loggedOut`
    /// in `runWebViewFallback()` (or clearing `loggedOut` per tick) makes the
    /// counter reach 1 and fails this.
    @Test func loggedOutBackoffSuppressesNeedsCookieRefreshFallback() async {
        let appState = AppState()
        let counter = FallbackCounter()
        let scraper = Support.makeScraper(
            appState: appState,
            // tick 1 arms the backoff; tick 2 would normally fall back.
            script: ResultScript([.notLoggedIn, .needsCookieRefresh]),
            counter: counter,
            domSuccess: Support.domScrapeUsage()
        )
        scraper.attach(appState: appState)

        await Support.tick(scraper) // .notLoggedIn → loggedOut = true
        #expect(scraper.loggedOut)

        await Support.tick(scraper) // .needsCookieRefresh → must be suppressed

        #expect(counter.value == 0)
        #expect(scraper.webView == nil)
        #expect(appState.usage == .empty)
        #expect(scraper.loggedOut)
    }

    /// GAP 2 — persistence across automatic ticks. While logged out, N automatic
    /// `.needsCookieRefresh` ticks never instantiate the WebView and the flag
    /// stays set. (The bug — clearing `loggedOut` at the top of every `scrape()`
    /// — would let every tick fall back, so counter == N.)
    @Test func loggedOutBackoffPersistsAcrossManyAutomaticTicks() async {
        let appState = AppState()
        let counter = FallbackCounter()
        let scraper = Support.makeScraper(
            appState: appState,
            script: ResultScript([.notLoggedIn, .needsCookieRefresh]),
            counter: counter,
            domSuccess: Support.domScrapeUsage()
        )
        scraper.attach(appState: appState)

        await Support.tick(scraper) // arm backoff
        for _ in 0 ..< 5 {
            await Support.tick(scraper) // each returns .needsCookieRefresh
        }

        #expect(counter.value == 0)
        #expect(scraper.webView == nil)
        #expect(scraper.loggedOut)
    }

    /// GAP 3 — explicit re-probe clears the backoff. After the backoff is armed,
    /// a `forceRefresh()` (the entry wake / Refresh Now / window-open use) clears
    /// `loggedOut` and allows a fresh full attempt, so a `.needsCookieRefresh` on
    /// that pass DOES enter the WebView fallback. Tested via the real method, not
    /// by poking the flag.
    @Test func forceRefreshClearsBackoffAndReenablesFallback() async {
        let appState = AppState()
        let counter = FallbackCounter()
        let scraper = Support.makeScraper(
            appState: appState,
            script: ResultScript([.notLoggedIn, .needsCookieRefresh]),
            counter: counter,
            domSuccess: Support.domScrapeUsage()
        )
        scraper.attach(appState: appState)

        await Support.tick(scraper) // arm backoff
        #expect(scraper.loggedOut)

        await Support.forceTick(scraper) // forceRefresh clears it → fallback runs

        #expect(counter.value == 1)
        #expect(appState.usage == Support.domScrapeUsage())
    }

    /// GAP 4 — the `/login`-detection navigation hook arms the backoff. Drive the
    /// real `WKNavigationDelegate` callback with a login URL and assert the
    /// observable effect: `loggedOut` set, WebView torn down.
    @Test func loginNavigationDetectionArmsBackoff() throws {
        let appState = AppState()
        let fetch: @Sendable () async -> UsageFetchResult = { .needsCookieRefresh }
        let scraper = QuotaScraper(fetchUsage: fetch)
        scraper.attach(appState: appState)
        #expect(!scraper.loggedOut)

        // Build a real ephemeral WebView, then simulate landing on /login.
        scraper.buildEphemeralWebView()
        let webView = try #require(scraper.currentWebView())
        let loginURL = try #require(URL(string: "https://claude.ai/login"))
        webView.load(URLRequest(url: loginURL))
        scraper.webView(webView, didFinish: nil)

        #expect(scraper.loggedOut)
        #expect(scraper.webView == nil)
    }

    /// GAP 5 — single-flight. Overlapping triggers while a fetch is in flight
    /// don't stack a second pass: only one fallback entry results from two
    /// near-simultaneous triggers against a single in-flight fetch.
    @Test func overlappingTriggersDoNotStackASecondPass() async {
        let appState = AppState()
        let counter = FallbackCounter()
        let scraper = Support.makeScraper(
            appState: appState,
            script: ResultScript([.needsCookieRefresh]),
            counter: counter,
            domSuccess: Support.domScrapeUsage()
        )
        scraper.attach(appState: appState)

        // Two synchronous triggers before the first fetch resolves: the second
        // hits the single-flight guard and is dropped.
        scraper.scrape()
        scraper.scrape()
        await scraper.awaitInFlight()

        #expect(counter.value == 1)
    }
}
