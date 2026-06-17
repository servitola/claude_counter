import Foundation
import Testing
import WebKit
@testable import ClaudeCounter

// MARK: - QuotaScraperOrchestrationTests

/// API-first orchestration of `QuotaScraper.scrape()` (Task 6). Every anchor
/// asserts an OBSERVABLE end state — `AppState.usage`, the `scraper.webView`
/// reference, and the fallback-entry counter — never a "was this method called"
/// spy assertion.
///
/// The scraper is driven through two injected seams:
/// - `fetchUsage` substitutes a scripted `UsageFetchResult` (no network).
/// - `runFallback` replaces the real ephemeral-WebView body so a test can both
///   count fallback entries (the production WebView-instantiation count) and
///   simulate a DOM-scrape success by populating `AppState` — without ever
///   building a real `WKWebView`.
@MainActor
struct QuotaScraperOrchestrationTests {
    // MARK: - Fixtures

    private static func sampleUsage() -> ClaudeUsage {
        ClaudeUsage(
            currentPercent: 7,
            weeklyPercent: 42,
            currentResetAt: Date(timeIntervalSince1970: 1_700_000_000),
            weeklyResetAt: Date(timeIntervalSince1970: 1_700_500_000),
            updatedAt: Date(timeIntervalSince1970: 1_699_999_999)
        )
    }

    private static func domScrapeUsage() -> ClaudeUsage {
        ClaudeUsage(
            currentPercent: 13,
            weeklyPercent: 88,
            currentResetAt: nil,
            weeklyResetAt: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_111_111)
        )
    }

    /// A scripted result source: pops from `results` in order, repeating the
    /// last element once exhausted.
    private final class ResultScript: @unchecked Sendable {
        private let lock = NSLock()
        private var results: [UsageFetchResult]
        private var index = 0

        init(_ results: [UsageFetchResult]) {
            self.results = results
        }

        func next() -> UsageFetchResult {
            lock.lock()
            defer { lock.unlock() }
            let value = results[min(index, results.count - 1)]
            index += 1
            return value
        }
    }

    /// Mutable counter shared with the injected fallback seam.
    private final class FallbackCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func bump() {
            lock.lock()
            defer { lock.unlock() }
            count += 1
        }

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }

    /// Build a scraper wired to a scripted API seam. The fallback seam counts
    /// entries and, when `domSuccess` is provided, populates `AppState` to
    /// simulate a DOM-scrape success on the fallback path.
    private func makeScraper(
        appState: AppState,
        script: ResultScript,
        counter: FallbackCounter,
        domSuccess: ClaudeUsage? = nil
    )
        -> QuotaScraper
    {
        QuotaScraper(
            fetchUsage: { script.next() },
            runFallback: { [weak appState] in
                counter.bump()
                if let domSuccess { appState?.usage = domSuccess }
            }
        )
    }

    /// Run one orchestrator pass and await the async fetch + MainActor apply.
    private func tick(_ scraper: QuotaScraper) async {
        scraper.scrape()
        await scraper.awaitInFlight()
    }

    // MARK: - Anchors

    @Test func apiSuccessLeavesWebViewNilAndPopulatesState() async {
        let appState = AppState()
        let counter = FallbackCounter()
        let scraper = makeScraper(
            appState: appState,
            script: ResultScript([.success(Self.sampleUsage())]),
            counter: counter
        )
        scraper.attach(appState: appState)

        await tick(scraper)

        #expect(appState.usage == Self.sampleUsage())
        #expect(scraper.webView == nil)
        #expect(counter.value == 0)
    }

    @Test func needsCookieRefreshFallbackPopulatesStateViaDomScrape() async {
        let appState = AppState()
        let counter = FallbackCounter()
        let scraper = makeScraper(
            appState: appState,
            script: ResultScript([.needsCookieRefresh]),
            counter: counter,
            domSuccess: Self.domScrapeUsage()
        )
        scraper.attach(appState: appState)

        await tick(scraper)

        #expect(appState.usage == Self.domScrapeUsage())
        #expect(counter.value >= 1)
    }

    @Test func decodeFailedFallbackPopulatesStateViaDomScrape() async {
        let appState = AppState()
        let counter = FallbackCounter()
        let scraper = makeScraper(
            appState: appState,
            script: ResultScript([.decodeFailed]),
            counter: counter,
            domSuccess: Self.domScrapeUsage()
        )
        scraper.attach(appState: appState)

        await tick(scraper)

        #expect(appState.usage == Self.domScrapeUsage())
        #expect(counter.value >= 1)
    }

    @Test func repeatedNotLoggedInKeepsWebViewNilAcrossTicks() async {
        let appState = AppState()
        let counter = FallbackCounter()
        let scraper = makeScraper(
            appState: appState,
            script: ResultScript([.notLoggedIn]),
            counter: counter,
            domSuccess: Self.domScrapeUsage()
        )
        scraper.attach(appState: appState)

        for _ in 0 ..< 4 {
            await tick(scraper)
        }

        #expect(scraper.webView == nil)
        #expect(counter.value == 0)
        #expect(appState.usage == .empty)
    }

    @Test func wakeAfterNotLoggedInReprobesAndPopulatesState() async {
        let appState = AppState()
        let counter = FallbackCounter()
        // First the logged-out result, then success on the re-probe.
        let scraper = makeScraper(
            appState: appState,
            script: ResultScript([.notLoggedIn, .success(Self.sampleUsage())]),
            counter: counter
        )
        scraper.attach(appState: appState)

        await tick(scraper) // logged out — backoff set
        #expect(appState.usage == .empty)

        // Wake forces a fresh scrape; clear-at-top re-probes the API.
        await tick(scraper)

        #expect(appState.usage == Self.sampleUsage())
        #expect(scraper.webView == nil)
        #expect(counter.value == 0)
    }

    @Test func windowOpenAfterNotLoggedInReprobesAndPopulatesState() async {
        let appState = AppState()
        let counter = FallbackCounter()
        let scraper = makeScraper(
            appState: appState,
            script: ResultScript([.notLoggedIn, .success(Self.sampleUsage())]),
            counter: counter
        )
        scraper.attach(appState: appState)

        await tick(scraper) // logged out
        #expect(appState.usage == .empty)

        // The window-open re-probe routes through scrape() (same as wake).
        await tick(scraper)

        #expect(appState.usage == Self.sampleUsage())
        #expect(scraper.webView == nil)
    }

    @Test func transportErrorLeavesStateUnchangedAndWebViewNil() async {
        let appState = AppState()
        let preset = Self.sampleUsage()
        appState.usage = preset
        let counter = FallbackCounter()
        let scraper = makeScraper(
            appState: appState,
            script: ResultScript([.transport(URLError(.timedOut))]),
            counter: counter,
            domSuccess: Self.domScrapeUsage()
        )
        scraper.attach(appState: appState)

        await tick(scraper)

        #expect(appState.usage == preset)
        #expect(scraper.webView == nil)
        #expect(counter.value == 0)
    }
}
