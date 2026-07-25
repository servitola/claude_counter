import Foundation
internal import os

// MARK: - CodexFetchResult

/// Typed outcome of one `CodexUsageClient.fetch()`.
enum CodexFetchResult {
    /// A populated snapshot mapped from a decodable usage response.
    case success(ProviderUsage)
    /// No local token, or the backend rejected it (401/403) — run `codex login`.
    case needsReauth
    /// A 200 with JSON that could not be mapped, or an unexpected status.
    case decodeFailed
    /// A networking/transport failure (no response).
    case transport(any Error)
}

// MARK: - CodexUsageClient

/// Reads the Codex CLI token from `~/.codex/auth.json` and fetches usage from
/// the ChatGPT backend. No cookies, no WebView: unlike the Claude path, Codex
/// already owns a logged-in session on disk, so we just present its bearer
/// token. Security: the token is NEVER logged — only status codes and outcomes.
struct CodexUsageClient: Sendable {
    /// Backend usage endpoint. Built once; `precondition` if the literal is ever
    /// rejected (mirrors `QuotaScraper.usageURL`).
    static let usageURL: URL = {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            preconditionFailure("Static URL string is invalid")
        }
        return url
    }()

    private let session: URLSession
    let auth: CodexAuthStore
    let log: @Sendable (String) -> Void

    init(
        configuration: URLSessionConfiguration = Self.productionConfiguration(),
        auth: CodexAuthStore = CodexAuthStore(),
        log: @escaping @Sendable (String)
            -> Void = { AppLog.codex.debug("\($0, privacy: .public)") }
    ) {
        self.session = URLSession(configuration: configuration)
        self.auth = auth
        self.log = log
    }

    /// Ephemeral session with no cookie jar — this call is bearer-token only.
    static func productionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return config
    }

    /// Read the local token, GET `/wham/usage`, classify, and map.
    func fetch() async -> CodexFetchResult {
        guard let creds = auth.read() else {
            log("auth missing — needs reauth")
            return .needsReauth
        }

        let data: Data
        let http: HTTPURLResponse
        do {
            let (payload, response) = try await session.data(for: buildRequest(creds))
            guard let httpResponse = response as? HTTPURLResponse else {
                return .transport(URLError(.badServerResponse))
            }
            data = payload
            http = httpResponse
        } catch {
            log("usage transport error")
            return .transport(error)
        }

        switch http.statusCode {
        case 200:
            break

        case 401, 403:
            log("usage status=\(http.statusCode) — needs reauth")
            return .needsReauth

        default:
            log("usage status=\(http.statusCode)")
            return .decodeFailed
        }

        guard
            let response = try? JSONDecoder().decode(CodexUsageResponse.self, from: data),
            let usage = CodexUsageMapper.map(response)
        else {
            log("usage decode failed")
            return .decodeFailed
        }
        log("usage ok")
        return .success(usage)
    }

    /// Build the authenticated GET request. Security: the bearer token is only
    /// ever set here and never logged.
    private func buildRequest(_ creds: CodexAuth) -> URLRequest {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountId = creds.accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "chatgpt-account-id")
        }
        request.setValue(WebViewFactory.safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
