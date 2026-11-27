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
    private weak var mainWebView: WKWebView?

    func load(_ url: URL, in webView: WKWebView) {
        targetURL = url
        mainWebView = webView
        webView.load(URLRequest(url: url))
    }

    /// Google's own pages carry claude.ai in redirect_uri/origin query params,
    /// so only the popup landing on the claude.ai host itself ends the flow.
    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        guard webView === authWebView, webView.url?.host == "claude.ai" else { return }
        closeAuthPopup()
        if let targetURL {
            mainWebView?.load(URLRequest(url: targetURL))
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
            // Google rejects sign-in from a WKWebView whose UA lacks Safari's.
            child.customUserAgent = webView.customUserAgent
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
            closeAuthPopup()
        }
    }

    private func closeAuthPopup() {
        authWebView?.removeFromSuperview()
        authWebView = nil
    }
}

// swiftlint:enable implicitly_unwrapped_optional
