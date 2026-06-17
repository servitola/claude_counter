import Foundation

/// `/usage` response classification, factored out of `UsageAPIClient` so neither
/// file grows past the length limit (mirrors the `OffHostRedirectGuard` split).
/// Classification order is load-bearing (tech-spec Data Models): the Cloudflare
/// challenge check and every auth check (401, `/login` redirect, login HTML body)
/// run BEFORE any JSON decode, so a login page never resolves to `.decodeFailed`.
extension UsageAPIClient {
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
