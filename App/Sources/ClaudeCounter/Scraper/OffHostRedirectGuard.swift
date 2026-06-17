import Foundation

/// `URLSessionTaskDelegate` that strips the `Cookie` header on any redirect that
/// leaves claude.ai (Decision 2). On-host redirects are followed unchanged. The
/// delegate holds no per-request state, so it is safe to share across the
/// session's tasks.
final class OffHostRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let host = request.url?.host else {
            completionHandler(request)
            return
        }
        if Self.isClaudeHost(host) {
            completionHandler(request)
            return
        }
        // Off-host: strip the Cookie header so credentials never leave claude.ai.
        var stripped = request
        stripped.setValue(nil, forHTTPHeaderField: "Cookie")
        completionHandler(stripped)
    }

    private static func isClaudeHost(_ host: String) -> Bool {
        host.caseInsensitiveCompare(UsageAPIClient.host) == .orderedSame
            || host.lowercased().hasSuffix(".\(UsageAPIClient.host)")
    }
}
