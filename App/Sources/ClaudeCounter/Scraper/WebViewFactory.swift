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
        if blockHeavy {
            // Hidden scraper view — disable gestures and link previews to
            // avoid allocating unnecessary recognizers and hover state.
            webView.allowsLinkPreview = false
            webView.allowsBackForwardNavigationGestures = false
        }
        return webView
    }

    /// Evict only WebKit's HTTP resource cache (disk + memory) from the
    /// shared `.default()` store — the exact store every WebView here uses.
    ///
    /// claude.ai ships content-hashed asset bundles several times a week.
    /// `WKWebsiteDataStore` caches every new build but never evicts the old
    /// ones, so `WebKit/NetworkCache` grows unbounded (observed at 700 MB+).
    /// Purging on launch resets it; assets re-download lazily on first use.
    ///
    /// Cookies and localStorage are deliberately excluded, so the claude.ai
    /// login survives. `removeData` is asynchronous and must not be awaited
    /// on the main thread — fire and forget.
    @MainActor
    static func purgeResourceCache() {
        let types: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache
        ]
        WKWebsiteDataStore.default().removeData(
            ofTypes: types,
            modifiedSince: .distantPast
        ) {}
    }

    /// The Safari user-agent string used for every claude.ai request.
    ///
    /// Exposed (not `private`) so `UsageAPIClient` reuses this single source of
    /// truth instead of hand-copying the literal: Cloudflare gates on the UA
    /// matching the WebView that `cf_clearance` was issued against, so the
    /// URLSession fetch and the WebView must send byte-identical strings.
    static let safariUserAgent = """
    Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) \
    AppleWebKit/605.1.15 (KHTML, like Gecko) \
    Version/18.0 Safari/605.1.15
    """
}
