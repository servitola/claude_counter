import WebKit

/// Shared WKWebView factory. `WKWebsiteDataStore.default()` persists
/// cookies/localStorage to `~/Library/WebKit/<bundle-id>/`, so the
/// claude.ai login survives app restarts.
///
/// `blockHeavy: true` attaches the ContentBlocker rule list — drops
/// images, fonts, media, popups, pings, and known analytics domains.
/// Use it for the hidden scraper view; the visible window passes
/// `false` so login flows render normally.
enum WebViewFactory {
    @MainActor
    static func make(blockHeavy: Bool = false) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.setValue(true, forKey: "javaScriptEnabled")
        if blockHeavy, let list = ContentBlocker.shared.ruleList {
            config.userContentController.add(list)
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = safariUserAgent
        return webView
    }

    private static let safariUserAgent = """
    Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) \
    AppleWebKit/605.1.15 (KHTML, like Gecko) \
    Version/18.0 Safari/605.1.15
    """
}
