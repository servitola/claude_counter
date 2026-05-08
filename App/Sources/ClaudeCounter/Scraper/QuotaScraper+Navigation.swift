import Foundation
import WebKit

// `WKNavigation!` parameter types come straight from the WebKit SDK.
// We can't change those signatures so we accept the IUOs in this file.
// swiftlint:disable implicitly_unwrapped_optional

extension QuotaScraper: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        let url = webView.url?.absoluteString ?? ""
        if url.contains("/login") {
            AppLog.scraper.notice("Auth required — skipping until user logs in")
            tearDown()
            return
        }
        if url.contains("about:blank") { return }
        // SPA needs time to render the React tree. Start polling
        // 1s after didFinish; the extract handler retries every
        // `pollInterval` until found=true or `maxExtractAttempts`.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            Task { @MainActor in self?.extract() }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        AppLog.scraper.error("Navigation failed: \(error.localizedDescription, privacy: .public)")
        handleFailure()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        AppLog.scraper.error(
            "Provisional fail: \(error.localizedDescription, privacy: .public)"
        )
        handleFailure()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        AppLog.scraper.error("WebContent process terminated mid-scrape")
        handleFailure()
    }
}

// swiftlint:enable implicitly_unwrapped_optional
