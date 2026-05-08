import AppKit
import WebKit

/// Standalone window with claude.ai/settings/usage in a WKWebView.
/// Standard traffic-light buttons, resizable, persists size between launches.
@MainActor
final class UsageWindow {
    static let shared = UsageWindow()

    private var window: NSWindow?
    private let coordinator = WebViewCoordinator()

    private init() {}

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        window = makeWindow()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Claude Usage"
        win.isReleasedWhenClosed = false
        win.center()
        win.setFrameAutosaveName("ClaudeCounter.UsageWindow")
        let webView = WebViewFactory.make()
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.autoresizingMask = [.width, .height]
        webView.frame = win.contentView!.bounds
        win.contentView?.addSubview(webView)
        coordinator.load(QuotaScraper.usageURL, in: webView)
        return win
    }
}
