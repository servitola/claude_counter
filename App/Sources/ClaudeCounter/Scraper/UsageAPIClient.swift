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

    // Production seam wired in by Task 6 (the scrape loop); unreferenced until
    // then but exercised by the smoke harness.
    // periphery:ignore
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
    private let orgStore: OrgIDStore
    private let cookies: CookieSource
    private let log: @Sendable (String) -> Void

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
        if let cached = orgStore.read() {
            log("org uuid cache hit")
            return .resolved(cached)
        }
        log("org uuid cache miss")

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

        if let authResult = authResult(for: data, response: response) {
            orgStore.invalidate()
            log("org discovery auth failure status=\(response.statusCode)")
            return .failed(authResult)
        }

        guard response.statusCode == 200 else {
            log("org discovery non-200 status=\(response.statusCode)")
            return .failed(.decodeFailed)
        }

        guard
            let orgs = try? UsageAPIModels.decoder.decode([OrgSummary].self, from: data),
            let uuid = pickOrg(from: orgs)
        else {
            orgStore.invalidate()
            log("org discovery empty or undecodable")
            return .failed(.decodeFailed)
        }

        orgStore.write(uuid)
        log("org discovery ok count=\(orgs.count)")
        return .resolved(uuid)
    }

    /// Pick the org uuid: the first one. The API returns the active org first
    /// and `OrgSummary` has no active flag, so "first" is the deterministic pick.
    func pickOrg(from orgs: [OrgSummary]) -> String? {
        orgs.first?.uuid
    }
}

private extension UsageAPIClient {
    /// Classify a `/usage` response. The challenge check and all auth checks
    /// (401, /login redirect, login HTML body) run BEFORE any JSON decode.
    func classifyUsage(data: Data, response: HTTPURLResponse) async -> UsageFetchResult {
        if response.statusCode == 403, isChallenge(data: data, response: response) {
            log("usage classified=needsCookieRefresh status=403")
            // Cache stays — the uuid is still valid; only cookies are stale.
            return .needsCookieRefresh
        }

        if let authResult = authResult(for: data, response: response) {
            orgStore.invalidate()
            log("usage classified=notLoggedIn status=\(response.statusCode)")
            return authResult
        }

        guard response.statusCode == 200 else {
            log("usage non-200 status=\(response.statusCode)")
            return .decodeFailed
        }

        guard
            let decoded = try? UsageAPIModels.decoder.decode(UsageResponse.self, from: data),
            let usage = UsageMapper.map(decoded)
        else {
            log("usage classified=decodeFailed status=200")
            return .decodeFailed
        }

        await writeBackCookies(from: response)
        log("usage classified=success status=200")
        return .success(usage)
    }

    /// `.notLoggedIn` for 401, a `/login`-path response (after a redirect), or
    /// an HTML login-page body. `nil` when none apply.
    func authResult(for data: Data, response: HTTPURLResponse) -> UsageFetchResult? {
        if response.statusCode == 401 { return .notLoggedIn }
        if response.url?.path.contains("/login") == true { return .notLoggedIn }
        if isHTML(response), isLoginPage(data: data) { return .notLoggedIn }
        return nil
    }

    func isHTML(_ response: HTTPURLResponse) -> Bool {
        let type = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        return type.contains("text/html")
    }

    func isLoginPage(data: Data) -> Bool {
        guard let body = String(data: data, encoding: .utf8)?.lowercased() else { return false }
        return body.contains("log in to claude")
            || body.contains("action=\"/login\"")
            || body.contains("/login")
    }

    func isChallenge(data: Data, response: HTTPURLResponse) -> Bool {
        guard isHTML(response) else { return false }
        guard let body = String(data: data, encoding: .utf8)?.lowercased() else { return false }
        return body.contains("just a moment") || body.contains("checking your browser")
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

    func writeBackCookies(from response: HTTPURLResponse) async {
        guard let url = response.url else { return }
        let setCookies = setCookieFields(from: response)
        guard !setCookies.isEmpty else { return }
        await cookies.writeBack(setCookies, url)
    }

    /// Extract `Set-Cookie` field values. `allHeaderFields` folds repeats into
    /// one comma-joined string, so re-emit one field per parsed cookie for
    /// CookieBridge's RFC-6265 comma-safe path; else the raw folded value.
    func setCookieFields(from response: HTTPURLResponse) -> [String] {
        if let url = response.url {
            let fields = response.allHeaderFields.reduce(into: [String: String]()) { acc, pair in
                if let key = pair.key as? String, let value = pair.value as? String {
                    acc[key] = value
                }
            }
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
            if !cookies.isEmpty {
                return cookies
                    .map { "\($0.name)=\($0.value); Domain=\($0.domain); Path=\($0.path)" }
            }
        }
        if let raw = response.value(forHTTPHeaderField: "Set-Cookie") {
            return [raw]
        }
        return []
    }
}
