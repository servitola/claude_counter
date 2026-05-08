import Foundation
import WebKit

extension QuotaScraper {
    func extract() {
        guard let webView = currentWebView() else { return }
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
        dumpDebug(payload)
        if let parsed = QuotaParser.parse(payload) {
            appStateRef()?.usage = parsed
        }
        // Always tear down — even on parse failure the next 60s tick
        // gets a fresh webview. Holding a stale one wastes memory.
        finishScrape()
    }

    /// Always-on dump of the latest scrape to `/tmp/claude_counter_debug.txt`.
    /// Unified logging filters non-Apple-signed bundles aggressively;
    /// this file is the only runtime visibility we get on user machines.
    private func dumpDebug(_ payload: QuotaPayload) {
        let raw = payload.raw.prefix(2000)
        let pattern = payload.matchedPattern ?? "nil"
        let matchText = payload.matchedText ?? "(no match)"
        let resetMinutes = payload.resetMinutes.map(String.init) ?? "nil"
        let out = """
        scraped at: \(Date())
        percentages: \(payload.textPercents)
        barPercents: \(payload.barPercents)
        resetMinutes: \(resetMinutes)
        matchedPattern: \(pattern)
        matchedText: \(matchText)

        --- raw aggregated text (first 2000 chars) ---
        \(raw)
        """
        try? out.write(
            toFile: "/tmp/claude_counter_debug.txt",
            atomically: true,
            encoding: .utf8
        )
    }
}
