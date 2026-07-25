import WebKit

// `WKNavigation!` parameter types come straight from the WebKit SDK.
// We can't change those signatures so we accept the IUOs in this file.
// swiftlint:disable implicitly_unwrapped_optional

/// Navigation + UI delegate for the visible usage WebView.
/// Handles Google OAuth popups (claude.ai login flow) and crash recovery.
@MainActor
final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    var targetURL: URL?
    private var authWebView: WKWebView?

    func load(_ url: URL, in webView: WKWebView) {
        targetURL = url
        webView.load(URLRequest(url: url))
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        let url = webView.url?.absoluteString ?? ""
        if url.contains("claude.ai"), authWebView != nil {
            authWebView?.removeFromSuperview()
            authWebView = nil
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if let url = targetURL {
            webView.load(URLRequest(url: url))
        } else {
            webView.reload()
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith config: WKWebViewConfiguration,
        for action: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    )
        -> WKWebView?
    {
        let host = action.request.url?.host ?? ""
        if host.contains("google") || host.contains("accounts") {
            let child = WKWebView(frame: webView.bounds, configuration: config)
            child.autoresizingMask = [.width, .height]
            child.navigationDelegate = self
            child.uiDelegate = self
            webView.addSubview(child)
            authWebView = child
            return child
        }
        if action.targetFrame == nil, let url = action.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView === authWebView {
            authWebView?.removeFromSuperview()
            authWebView = nil
        }
    }
}

// swiftlint:enable implicitly_unwrapped_optional
