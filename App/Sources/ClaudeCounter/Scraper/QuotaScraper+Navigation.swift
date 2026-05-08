import Foundation
import WebKit

extension QuotaScraper: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        let url = webView.url?.absoluteString ?? ""
        if url.contains("/login") {
            NSLog("[Scraper] Auth required — skip until user logs in")
            tearDown()
            return
        }
        if url.contains("about:blank") { return }
        // SPA needs time to render the React tree before extracting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            Task { @MainActor in self?.extract() }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        NSLog("[Scraper] Failed: \(error.localizedDescription)")
        handleFailure()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        NSLog("[Scraper] Provisional fail: \(error.localizedDescription)")
        handleFailure()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("[Scraper] WebContent process terminated mid-scrape")
        handleFailure()
    }
}
