import WebKit

/// Shared WKWebView factory. `WKWebsiteDataStore.default()` persists
/// cookies/localStorage to `~/Library/WebKit/<bundle-id>/`, so the
/// claude.ai login survives app restarts.
enum WebViewFactory {
    @MainActor
    static func make() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.setValue(true, forKey: "javaScriptEnabled")
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
