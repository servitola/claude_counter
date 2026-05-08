import Foundation
import WebKit

/// Compiles a WKContentRuleList that blocks heavy / unnecessary resources
/// for the scraper WebView. Cuts page weight (no images, fonts, media,
/// analytics) → smaller WebContent process during the scrape window.
///
/// We deliberately do NOT block: document, script, style-sheet, raw,
/// fetch, xhr — claude.ai is a React SPA, the DOM tree we read only
/// exists after JS executes.
@MainActor
final class ContentBlocker {
    static let shared = ContentBlocker()

    private(set) var ruleList: WKContentRuleList?

    func prewarm() {
        guard ruleList == nil else { return }
        guard let store = WKContentRuleListStore.default() else { return }
        store.compileContentRuleList(
            forIdentifier: "ClaudeCounterBlocker",
            encodedContentRuleList: Self.rulesJSON
        ) { [weak self] list, error in
            Task { @MainActor in
                if let error {
                    AppLog.blocker.error(
                        "compile failed: \(error.localizedDescription, privacy: .public)"
                    )
                    return
                }
                self?.ruleList = list
                AppLog.blocker.info("rule list compiled")
            }
        }
    }

    private static let rulesJSON: String = {
        let resourceBlock = ["image", "font", "media", "popup", "ping"]
            .map { type in
                """
                {"trigger":{"url-filter":".*","resource-type":["\(
                    type
                )"]},"action":{"type":"block"}}
                """
            }
        let trackerBlock = [
            "google-analytics", "googletagmanager", "doubleclick",
            "segment\\\\.com", "segment\\\\.io", "mixpanel",
            "intercom\\\\.io", "intercomcdn", "hotjar",
            "fullstory", "heap\\\\.io", "amplitude", "logrocket",
            "datadog", "sentry\\\\.io", "newrelic"
        ].map { host in
            """
            {"trigger":{"url-filter":"\(host)"},"action":{"type":"block"}}
            """
        }
        return "[" + (resourceBlock + trackerBlock).joined(separator: ",") + "]"
    }()
}
