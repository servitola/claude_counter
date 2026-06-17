import Foundation
internal import os

// MARK: - UsageFetchResult

/// Typed outcome of one `UsageAPIClient.fetch()`. Task 5 owns this enum.
///
/// Classification order is load-bearing (tech-spec Data Models): a 200 whose
/// body is the login page resolves to `.notLoggedIn`, NOT `.decodeFailed` —
/// `.notLoggedIn` drives the Decision-7 backoff while `.decodeFailed` triggers
/// the expensive DOM-scrape fallback.
enum UsageFetchResult {
    /// A populated snapshot mapped from a decodable usage response.
    case success(ClaudeUsage)
    /// 403 + Cloudflare "Just a moment…" challenge — `cf_clearance` needs refresh.
    case needsCookieRefresh
    /// 401, a redirect to `/login`, or a 200 whose body is the login page.
    case notLoggedIn
    /// A 200 with valid JSON that cannot be mapped to a usable `ClaudeUsage`.
    case decodeFailed
    /// A networking/transport failure (no response).
    case transport(any Error)
}

// MARK: - CookieSource

/// Seam between `UsageAPIClient` and the WebView cookie jar: read the outgoing
/// `Cookie` header value, write rotating `Set-Cookie`s back. Two `Sendable`
/// closures keep the client free of WebKit/`@MainActor` and let tests inject
/// stubs. `bridged` wraps a `CookieBridge` (Task 4), hopping to MainActor where
/// `WKHTTPCookieStore` is safe to touch.
struct CookieSource {
    let header: @Sendable () async -> String
    let writeBack: @Sendable ([String], URL) async -> Void

    /// Production seam wired in by Task 6 (the scrape loop) via
    /// `QuotaScraper.makeProductionFetch()`.
    @MainActor
    static func bridged(_ bridge: CookieBridge = CookieBridge()) -> Self {
        Self(
            header: { await bridge.cookieHeader() },
            writeBack: { headers, url in
                await bridge.writeBack(setCookieHeaders: headers, responseURL: url)
            }
        )
    }
}

// MARK: - UsageAPIClient

/// Networking core of the JSON-API scraper. Owns one `URLSession` with NO cookie
/// jar of its own (Decision 2): cookies come solely from the WebView store via
/// `CookieSource`, and `OffHostRedirectGuard` strips the `Cookie` header the
/// moment a redirect leaves claude.ai. `fetch()` discovers the org uuid (cached
/// in `OrgIDStore`), fetches `/usage` with the Safari UA + bridged cookies, and
/// returns a classified `UsageFetchResult`.
///
/// Security (Decision 6): cookie values and request headers are NEVER logged —
/// only value-free events (status code, result case, discovery outcome), via an
/// injectable `log` closure so tests can capture every line.
struct UsageAPIClient {
    /// Base host for every request. Cookies only ever reach this host.
    static let host = "claude.ai"

    private let session: URLSession
    // Accessed by the `UsageResponseClassifier` extension (separate file), so
    // these are module-internal rather than `private`.
    let orgStore: OrgIDStore
    let cookies: CookieSource
    let log: @Sendable (String) -> Void

    /// `configuration` is injectable so tests register a stub `URLProtocol`;
    /// `cookies` is the read + write-back seam; `log` is a value-free sink.
    init(
        configuration: URLSessionConfiguration = Self.productionConfiguration(),
        orgStore: OrgIDStore = OrgIDStore(),
        cookies: CookieSource,
        log: @escaping @Sendable (String)
            -> Void = { AppLog.scraper.debug("\($0, privacy: .public)") }
    ) {
        // `URLSession` retains its delegate strongly until invalidated, so the
        // guard does not need a separate stored reference.
        self.session = URLSession(
            configuration: configuration,
            delegate: OffHostRedirectGuard(),
            delegateQueue: nil
        )
        self.orgStore = orgStore
        self.cookies = cookies
        self.log = log
    }

    /// Production `URLSessionConfiguration`: no cookie jar (Decision 2).
    static func productionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        return config
    }

    /// Discover the org uuid (cached), fetch `/usage`, classify, and map.
    func fetch() async -> UsageFetchResult {
        let uuid: String
        switch await resolveOrgUUID() {
        case .resolved(let value):
            uuid = value

        case .failed(let result):
            return result
        }

        guard let url = usageURL(orgUUID: uuid) else { return .decodeFailed }

        let cookieHeader = await cookies.header()
        do {
            let (data, response) = try await get(url, cookieHeader: cookieHeader)
            return await classifyUsage(data: data, response: response)
        } catch {
            log("usage fetch transport error")
            return .transport(error)
        }
    }
}

private extension UsageAPIClient {
    enum OrgResolution {
        case resolved(String)
        case failed(UsageFetchResult)
    }

    /// Read the cached uuid; on a miss, `GET /api/organizations`, pick the
    /// active/first uuid, and cache it. Auth/empty failures invalidate the
    /// cache so the next tick re-discovers.
    func resolveOrgUUID() async -> OrgResolution {
        if let cached = cachedUUID() {
            return .resolved(cached)
        }

        guard let url = URL(string: "https://\(Self.host)/api/organizations") else {
            return .failed(.decodeFailed)
        }

        let cookieHeader = await cookies.header()
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await get(url, cookieHeader: cookieHeader)
        } catch {
            log("org discovery transport error")
            return .failed(.transport(error))
        }

        // Same challenge/auth/non-200 preamble the usage call runs, so a 403
        // Cloudflare challenge on cold start (empty cache + expired
        // `cf_clearance`) classifies as `.needsCookieRefresh`, not
        // `.decodeFailed`, and a 401/login page classifies as `.notLoggedIn`.
        if
            let preamble = classifyResponsePreamble(
                data: data, response: response, label: "org discovery"
            )
        {
            return .failed(preamble)
        }

        guard
            let orgs = try? UsageAPIModels.decoder.decode([OrgSummary].self, from: data),
            let uuid = pickOrg(from: orgs),
            Self.isValidUUID(uuid)
        else {
            orgStore.invalidate()
            log("org discovery empty, undecodable, or non-uuid")
            return .failed(.decodeFailed)
        }

        orgStore.write(uuid)
        log("org discovery ok count=\(orgs.count)")
        return .resolved(uuid)
    }

    /// Return the cached uuid only when it is present AND well-formed. A
    /// poisoned (non-UUID) cache entry is invalidated and treated as a miss, so
    /// discovery re-runs. `nil` means "no usable cache — discover".
    func cachedUUID() -> String? {
        guard let cached = orgStore.read() else {
            log("org uuid cache miss")
            return nil
        }
        if Self.isValidUUID(cached) {
            log("org uuid cache hit")
            return cached
        }
        orgStore.invalidate()
        log("org uuid cache invalid; re-discovering")
        return nil
    }

    /// Pick the org uuid: the first one. The API returns the active org first
    /// and `OrgSummary` has no active flag, so "first" is the deterministic pick.
    func pickOrg(from orgs: [OrgSummary]) -> String? {
        orgs.first?.uuid
    }

    /// Defense in depth: the uuid is interpolated raw into the `/usage` path, so
    /// reject anything that is not a well-formed UUID before it reaches the URL.
    /// A non-UUID is treated as a discovery failure (the cache is already
    /// invalidated by the caller), so the next tick re-discovers.
    static func isValidUUID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }
}

private extension UsageAPIClient {
    func usageURL(orgUUID: String) -> URL? {
        URL(string: "https://\(Self.host)/api/organizations/\(orgUUID)/usage")
    }

    /// Issue a GET with the Safari UA + bridged cookies. Cookie/UA headers are
    /// never logged (Decision 6).
    func get(_ url: URL, cookieHeader: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(WebViewFactory.safariUserAgent, forHTTPHeaderField: "User-Agent")
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

/// Internal (not `private`) so the `UsageResponseClassifier` extension in its own
/// file can trigger write-back after a successful decode.
extension UsageAPIClient {
    func writeBackCookies(from response: HTTPURLResponse) async {
        guard let url = response.url else { return }
        let setCookies = setCookieFields(from: response)
        guard !setCookies.isEmpty else { return }
        await cookies.writeBack(setCookies, url)
    }

    /// Forward the RAW `Set-Cookie` header value(s) to `CookieBridge` WITHOUT
    /// reconstruction, preserving `Secure`/`HttpOnly`/`Expires` and every other
    /// attribute. Foundation folds repeated `Set-Cookie` headers into a single
    /// comma-joined `allHeaderFields["Set-Cookie"]`; URLSession exposes no
    /// unfolded per-field accessor here, so the least-lossy path is to pass that
    /// raw folded value straight through as a single element. `CookieBridge`
    /// then parses it via `HTTPCookie.cookies(withResponseHeaderFields:)` (which
    /// handles the RFC-6265 comma hazard) and keeps only claude.ai-scoped jar
    /// entries.
    func setCookieFields(from response: HTTPURLResponse) -> [String] {
        guard let raw = response.value(forHTTPHeaderField: "Set-Cookie"), !raw.isEmpty else {
            return []
        }
        return [raw]
    }
}
