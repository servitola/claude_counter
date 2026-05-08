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
            isLoading = false
            return
        }
        // SPA needs time to render — wait then extract.
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
        retry()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("[Scraper] WebContent process terminated")
        retry()
    }

    private func retry() {
        isLoading = false
        guard retryCount < Self.maxRetries else { return }
        retryCount += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            Task { @MainActor in self?.scrape() }
        }
    }
}
