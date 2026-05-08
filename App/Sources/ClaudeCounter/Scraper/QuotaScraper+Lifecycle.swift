import Foundation
import WebKit

extension QuotaScraper {
    /// Schedule a hard kill of the current scrape if it hangs.
    func armWatchdog() {
        watchdog?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                NSLog("[Scraper] Watchdog fired — killing webview")
                self.tearDown()
            }
        }
        watchdog = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.watchdogTimeout, execute: item
        )
    }

    /// Drop the WKWebView. With no remaining strong refs the underlying
    /// WebContent / Networking / GPU XPC services exit on their own.
    func tearDown() {
        watchdog?.cancel()
        watchdog = nil
        if let wv = self.webView {
            wv.stopLoading()
            wv.navigationDelegate = nil
            wv.uiDelegate = nil
            // Loading about:blank releases the page DOM faster than
            // just dropping the reference.
            wv.load(URLRequest(url: URL(string: "about:blank")!))
        }
        self.webView = nil
    }

    /// Called by Navigation extension on failure. Retries once on the
    /// next runloop tick before giving up until the next 60s tick.
    func handleFailure() {
        let canRetry = retryCount < Self.maxRetries
        tearDown()
        if canRetry {
            retryCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                Task { @MainActor in self?.scrape() }
            }
        } else {
            retryCount = 0
        }
    }

    /// Called from extract handler when the scrape succeeds.
    func finishScrape() {
        retryCount = 0
        tearDown()
    }

    func currentWebView() -> WKWebView? { self.webView }
}
