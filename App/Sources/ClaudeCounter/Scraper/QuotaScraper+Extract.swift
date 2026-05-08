import Foundation
import WebKit

extension QuotaScraper {
    func extract() {
        guard let webView = currentWebView() else { return }
        extractAttempts += 1
        webView.evaluateJavaScript(Self.extractionJS) { [weak self] result, error in
            Task { @MainActor in
                self?.handle(result: result, error: error)
            }
        }
    }

    private func handle(result: Any?, error: (any Error)?) {
        if let error {
            AppLog.scraper.error("JS error: \(error.localizedDescription, privacy: .public)")
            handleFailure()
            return
        }
        guard let payload = QuotaPayload(jsResult: result) else {
            AppLog.scraper.error("JS returned non-dictionary")
            handleFailure()
            return
        }

        // SPA may not have rendered the data yet — keep polling until
        // either the JS finds it or we exhaust attempts. The watchdog
        // still bounds total scrape time.
        if !payload.found, extractAttempts < Self.maxExtractAttempts {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.pollInterval
            ) { [weak self] in
                Task { @MainActor in self?.extract() }
            }
            return
        }

        dumpDebug(payload)
        if let parsed = QuotaParser.parse(payload) {
            appStateRef()?.usage = parsed
        }
        // Always tear down — even on parse failure the next 60s tick
        // gets a fresh webview. Holding a stale one wastes memory.
        finishScrape()
    }

    /// Always-on dump of the latest scrape to
    /// `~/Library/Logs/ClaudeCounter/scrape-debug.txt`.
    private func dumpDebug(_ payload: QuotaPayload) {
        ScrapeDebugLog.default.write(Self.formatDebug(payload, now: Date()))
    }

    nonisolated static func formatDebug(_ payload: QuotaPayload, now: Date) -> String {
        let raw = payload.raw.prefix(2000)
        let pattern = payload.matchedPattern ?? "nil"
        let matchText = payload.matchedText ?? "(no match)"
        let resetMinutes = payload.resetMinutes.map(String.init) ?? "nil"
        return """
        scraped at: \(now)
        percentages: \(payload.textPercents)
        barPercents: \(payload.barPercents)
        resetMinutes: \(resetMinutes)
        matchedPattern: \(pattern)
        matchedText: \(matchText)

        --- raw aggregated text (first 2000 chars) ---
        \(raw)
        """
    }
}
