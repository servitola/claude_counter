import Foundation
import Testing
import WebKit
@testable import ClaudeCounter

// MARK: - QuotaScraperTestSupport

/// Shared seams + fixtures for the `QuotaScraper` orchestration suites
/// (`QuotaScraperOrchestrationTests`, `QuotaScraperBackoffTests`). Kept in one
/// place so both suites drive the scraper identically and stay under the
/// `file_length` cap.
///
/// The scraper is driven through two injected seams:
/// - `fetchUsage` substitutes a scripted `UsageFetchResult` (no network).
/// - `runFallback` replaces the real ephemeral-WebView body so a test can both
///   count fallback entries (the production WebView-instantiation count) and
///   simulate a DOM-scrape success by populating `AppState` — without ever
///   building a real `WKWebView`.
enum QuotaScraperTestSupport {
    // MARK: - Fixtures

    static func sampleUsage() -> ClaudeUsage {
        ClaudeUsage(
            currentPercent: 7,
            weeklyPercent: 42,
            currentResetAt: Date(timeIntervalSince1970: 1_700_000_000),
            weeklyResetAt: Date(timeIntervalSince1970: 1_700_500_000),
            updatedAt: Date(timeIntervalSince1970: 1_699_999_999)
        )
    }

    static func domScrapeUsage() -> ClaudeUsage {
        ClaudeUsage(
            currentPercent: 13,
            weeklyPercent: 88,
            currentResetAt: nil,
            weeklyResetAt: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_111_111)
        )
    }
}

// MARK: - ResultScript

/// A scripted result source: pops from `results` in order, repeating the last
/// element once exhausted.
final class ResultScript: @unchecked Sendable {
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

// MARK: - FallbackCounter

/// Mutable counter shared with the injected fallback seam — the production
/// WebView-instantiation count.
final class FallbackCounter: @unchecked Sendable {
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

@MainActor
extension QuotaScraperTestSupport {
    /// Build a scraper wired to a scripted API seam. The fallback seam counts
    /// entries and, when `domSuccess` is provided, populates `AppState` to
    /// simulate a DOM-scrape success on the fallback path.
    static func makeScraper(
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
                if let domSuccess {
                    appState?.usage = domSuccess
                }
            }
        )
    }

    /// Run one AUTOMATIC orchestrator pass (the 60 s `Timer` path) and await the
    /// async fetch + MainActor apply. Does NOT clear the Decision-7 backoff.
    static func tick(_ scraper: QuotaScraper) async {
        scraper.scrape()
        await scraper.awaitInFlight()
    }

    /// Run one EXPLICIT re-probe pass — the path system wake, "Refresh Now",
    /// and window-open take — and await it. Clears the Decision-7 backoff first.
    static func forceTick(_ scraper: QuotaScraper) async {
        scraper.forceRefresh()
        await scraper.awaitInFlight()
    }
}
