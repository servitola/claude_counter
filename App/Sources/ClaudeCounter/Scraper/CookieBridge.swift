import Foundation
import WebKit

/// The single seam between the WebView's cookie store and the URLSession-based
/// API client. Per Decision 2, `WKWebsiteDataStore`'s `httpCookieStore` is the
/// sole source of truth for claude.ai cookies; this bridge reads them out (so a
/// request can be built off-main without touching WebKit) and writes rotating
/// cookies back in from API responses.
///
/// `WKHTTPCookieStore` is async and MainActor-bound, so the whole type is
/// `@MainActor`. `read()`/`cookieHeader()` complete on MainActor and hand the
/// caller a plain value before any request is assembled.
///
/// Security (Decision 6): no cookie name or value is ever logged. Only counts
/// and the fixed host appear, and they go through an injectable `log` closure
/// so a test can capture every emitted line. The default closure forwards to
/// `AppLog.scraper`.
@MainActor
struct CookieBridge {
    /// The host this bridge will read and write. Cookies for any other host are
    /// filtered out on read and skipped on write-back.
    static let host = "claude.ai"

    private let store: WKWebsiteDataStore
    private let log: @MainActor (String) -> Void

    init(
        store: WKWebsiteDataStore = .default(),
        log: @escaping @MainActor (String)
            -> Void = { AppLog.scraper.debug("\($0, privacy: .public)") }
    ) {
        self.store = store
        self.log = log
    }

    // MARK: - Read (out)

    /// All `claude.ai`-scoped cookies from the store, as a plain value. Cookies
    /// for any other host are never returned, so they can never be attached to
    /// an outgoing request. Completes on MainActor before any request is built.
    func read() async -> [HTTPCookie] {
        let all = await store.httpCookieStore.allCookies()
        let scoped = all.filter { Self.isClaudeScoped($0.domain) }
        // Counts and host only — never a cookie name or value (Decision 6).
        log("cookie read host=\(Self.host) count=\(scoped.count)")
        return scoped
    }

    /// The `Cookie` request-header value built from the `claude.ai`-scoped
    /// cookies: `name=value` pairs joined by `; `. Empty when the store has no
    /// matching cookies.
    func cookieHeader() async -> String {
        let cookies = await read()
        return cookies
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    // MARK: - Write-back (in)

    /// Parse `Set-Cookie` header field(s) from a successful API response and
    /// insert the resulting `claude.ai`-scoped cookies back into the store.
    /// Non-claude cookies are skipped (defense in depth); unparseable entries
    /// are dropped silently.
    func writeBack(setCookieHeaders: [String], responseURL: URL) async {
        // `HTTPCookie.cookies(withResponseHeaderFields:for:)` reads a single
        // "Set-Cookie" value; join multiple fields with a comma the way a
        // server would so each is parsed.
        let joined = setCookieHeaders.joined(separator: ", ")
        let parsed = HTTPCookie.cookies(
            withResponseHeaderFields: ["Set-Cookie": joined],
            for: responseURL
        )

        var inserted = 0
        for cookie in parsed where Self.isClaudeScoped(cookie.domain) {
            await store.httpCookieStore.setCookie(cookie)
            inserted += 1
        }
        // Counts and host only — never a cookie name or value (Decision 6).
        log("cookie write-back host=\(Self.host) inserted=\(inserted)")
    }

    // MARK: - Host scoping

    /// True only for the bare host `claude.ai` or its leading-dot form
    /// `.claude.ai`. Lookalikes such as `notclaude.ai` and `claude.ai.evil.com`
    /// are rejected.
    static func isClaudeScoped(_ domain: String) -> Bool {
        let normalized = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        return normalized.caseInsensitiveCompare(host) == .orderedSame
    }
}
