import Foundation
import Testing
import WebKit
@testable import ClaudeCounter

// MARK: - QuotaScraperOrchestrationTests

/// API-first orchestration of `QuotaScraper.scrape()` (Task 6). Every anchor
/// asserts an OBSERVABLE end state — `AppState.usage`, the `scraper.webView`
/// reference, and the fallback-entry counter — never a "was this method called"
/// spy assertion. Shared seams/fixtures live in `QuotaScraperTestSupport`.
@MainActor
struct QuotaScraperOrchestrationTests {
    private typealias Support = QuotaScraperTestSupport

    @Test func apiSuccessLeavesWebViewNilAndPopulatesState() async {
        let appState = AppState()
        let counter = FallbackCounter()
        let scraper = Support.makeScraper(
            appState: appState,
            script: ResultScript([.success(Support.sampleUsage())]),
            counter: counter
        )
        scraper.attach(appState: appState)

        await Support.tick(scraper)

        #expect(appState.usage == Support.sampleUsage())
        #expect(scraper.webView == nil)
        #expect(counter.value == 0)
    }

    @Test func needsCookieRefreshFallbackPopulatesStateViaDomScrape() async {
        let appState = AppState()
        let counter = FallbackCounter()
        let scraper = Support.makeScraper(
            appState: appState,
            script: ResultScript([.needsCookieRefresh]),
            counter: counter,
            domSuccess: Support.domScrapeUsage()
        )
        scraper.attach(appState: appState)

        await Support.tick(scraper)

        #expect(appState.usage == Support.domScrapeUsage())
        #expect(counter.value >= 1)
    }

    @Test func decodeFailedFallbackPopulatesStateViaDomScrape() async {
        let appState = AppState()
        let counter = FallbackCounter()
        let scraper = Support.makeScraper(
            appState: appState,
            script: ResultScript([.decodeFailed]),
            counter: counter,
            domSuccess: Support.domScrapeUsage()
        )
        scraper.attach(appState: appState)

        await Support.tick(scraper)

        #expect(appState.usage == Support.domScrapeUsage())
        #expect(counter.value >= 1)
    }

    @Test func repeatedNotLoggedInKeepsWebViewNilAcrossTicks() async {
        let appState = AppState()
        let counter = FallbackCounter()
        let scraper = Support.makeScraper(
            appState: appState,
            script: ResultScript([.notLoggedIn]),
            counter: counter,
            domSuccess: Support.domScrapeUsage()
        )
        scraper.attach(appState: appState)

        for _ in 0 ..< 4 {
            await Support.tick(scraper)
        }

        #expect(scraper.webView == nil)
        #expect(counter.value == 0)
        #expect(appState.usage == .empty)
    }

    @Test func wakeAfterNotLoggedInReprobesAndPopulatesState() async {
        let appState = AppState()
        let counter = FallbackCounter()
        // First the logged-out result, then success on the re-probe.
        let scraper = Support.makeScraper(
            appState: appState,
            script: ResultScript([.notLoggedIn, .success(Support.sampleUsage())]),
            counter: counter
        )
        scraper.attach(appState: appState)

        await Support.tick(scraper) // logged out — backoff set
        #expect(appState.usage == .empty)
        #expect(scraper.loggedOut)

        // Wake routes through forceRefresh(); clears the backoff and re-probes.
        await Support.forceTick(scraper)

        #expect(appState.usage == Support.sampleUsage())
        #expect(scraper.webView == nil)
        #expect(counter.value == 0)
    }

    @Test func windowOpenAfterNotLoggedInReprobesAndPopulatesState() async {
        let appState = AppState()
        let counter = FallbackCounter()
        let scraper = Support.makeScraper(
            appState: appState,
            script: ResultScript([.notLoggedIn, .success(Support.sampleUsage())]),
            counter: counter
        )
        scraper.attach(appState: appState)

        await Support.tick(scraper) // logged out
        #expect(appState.usage == .empty)

        // The window-open re-probe routes through forceRefresh() (same as wake).
        await Support.forceTick(scraper)

        #expect(appState.usage == Support.sampleUsage())
        #expect(scraper.webView == nil)
    }

    @Test func transportErrorLeavesStateUnchangedAndWebViewNil() async {
        let appState = AppState()
        let preset = Support.sampleUsage()
        appState.usage = preset
        let counter = FallbackCounter()
        let scraper = Support.makeScraper(
            appState: appState,
            script: ResultScript([.transport(URLError(.timedOut))]),
            counter: counter,
            domSuccess: Support.domScrapeUsage()
        )
        scraper.attach(appState: appState)

        await Support.tick(scraper)

        #expect(appState.usage == preset)
        #expect(scraper.webView == nil)
        #expect(counter.value == 0)
    }
}
