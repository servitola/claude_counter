import Foundation

/// `URLSessionTaskDelegate` that strips credential headers on any redirect
/// that leaves `host` (or its subdomains). On-host redirects are followed
/// unchanged. Foundation already drops `Authorization` across hosts but
/// forwards `Cookie` and custom headers such as `chatgpt-account-id`
/// (verified with a local two-host redirect). Holds no per-request state, so
/// it is safe to share across the session's tasks.
final class OffHostRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    private let host: String
    private let sensitiveHeaders: [String]

    init(host: String, sensitiveHeaders: [String]) {
        self.host = host
        self.sensitiveHeaders = sensitiveHeaders
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(guarded(request))
    }

    func guarded(_ request: URLRequest) -> URLRequest {
        if let target = request.url?.host, isOwnHost(target) {
            return request
        }
        var stripped = request
        for header in sensitiveHeaders {
            stripped.setValue(nil, forHTTPHeaderField: header)
        }
        return stripped
    }

    private func isOwnHost(_ candidate: String) -> Bool {
        candidate.caseInsensitiveCompare(host) == .orderedSame
            || candidate.lowercased().hasSuffix(".\(host.lowercased())")
    }
}
