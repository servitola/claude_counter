import Foundation
import WebKit

extension QuotaScraper {
    func extract() {
        guard let wv = currentWebView() else { return }
        wv.evaluateJavaScript(Self.extractionJS) { [weak self] result, error in
            Task { @MainActor in
                self?.handle(result: result, error: error)
            }
        }
    }

    private func handle(result: Any?, error: Error?) {
        if let error {
            NSLog("[Scraper] JS error: \(error.localizedDescription)")
            handleFailure()
            return
        }
        guard let dict = result as? [String: Any] else {
            handleFailure()
            return
        }
        dumpDebug(dict)
        if let parsed = parse(dict) {
            appStateRef()?.usage = parsed
        }
        // Always tear down — even on parse failure the next 60s tick
        // gets a fresh webview. Holding a stale one wastes memory.
        finishScrape()
    }

    /// Always-on dump of the latest scrape to `/tmp/claude_counter_debug.txt`.
    /// NSLog from a non-Apple-signed bundle is filtered out of unified
    /// logging, so the file is the only visibility we have at runtime.
    private func dumpDebug(_ dict: [String: Any]) {
        let pcts = dict["percentages"] as? [Double] ?? []
        let bars = dict["barPercents"] as? [Double] ?? []
        let reset = dict["resetMinutes"].map { "\($0)" } ?? "nil"
        let pattern = dict["matchedPattern"].map { "\($0)" } ?? "nil"
        let matchText = dict["matchedText"] as? String ?? "(no match)"
        let raw = (dict["raw"] as? String ?? "(empty)").prefix(2000)
        let out = """
            scraped at: \(Date())
            percentages: \(pcts)
            barPercents: \(bars)
            resetMinutes: \(reset)
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
