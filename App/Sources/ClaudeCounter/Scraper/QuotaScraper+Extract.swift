import Foundation
import WebKit

extension QuotaScraper {
    func extract() {
        guard let webView else { isLoading = false; return }
        webView.evaluateJavaScript(Self.extractionJS) { [weak self] result, error in
            Task { @MainActor in
                self?.handle(result: result, error: error)
            }
        }
    }

    private func handle(result: Any?, error: Error?) {
        defer { isLoading = false }
        if let error {
            NSLog("[Scraper] JS error: \(error.localizedDescription)")
            return
        }
        guard let dict = result as? [String: Any] else { return }
        dumpDebug(dict)
        guard let parsed = parse(dict) else { return }
        appStateRef()?.usage = parsed
    }

    /// Always-on dump of the latest scrape to `/tmp/claude_counter_debug.txt`.
    /// Cheap, and the only way to see what the page actually returned
    /// (NSLog from a bundled .app is filtered out of unified logging
    /// for non-Apple-signed binaries).
    private func dumpDebug(_ dict: [String: Any]) {
        let pcts = dict["percentages"] as? [Double] ?? []
        let bars = dict["barPercents"] as? [Double] ?? []
        let reset = dict["resetMinutes"].map { "\($0)" } ?? "nil"
        let pattern = dict["matchedPattern"].map { "\($0)" } ?? "nil"
        let matchText = dict["matchedText"] as? String ?? "(no match)"
        let raw = dict["raw"] as? String ?? "(empty)"
        let out = """
            scraped at: \(Date())
            percentages: \(pcts)
            barPercents: \(bars)
            resetMinutes: \(reset)
            matchedPattern: \(pattern)
            matchedText: \(matchText)

            --- raw aggregated text ---
            \(raw)
            """
        try? out.write(
            toFile: "/tmp/claude_counter_debug.txt",
            atomically: true,
            encoding: .utf8
        )
    }
}
