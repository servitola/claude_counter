import Foundation

// MARK: - StubURLProtocol

/// Deterministic, path-routed `URLProtocol` stub for `UsageAPIClient` tests.
///
/// Routes are matched by URL path substring (or host, for off-host targets)
/// and installed on an injected `URLSessionConfiguration`. No live network is
/// ever touched. Recorded requests let tests assert on outgoing headers (e.g.
/// the off-host Cookie-strip check).
///
/// `URLProtocol` instances are created by the loading system on arbitrary
/// threads, so the shared route table and the recorded-request log are guarded
/// by a single lock. The mutable statics are `nonisolated(unsafe)` and only ever
/// touched behind that lock.
final class StubURLProtocol: URLProtocol {
    // MARK: - Route

    /// One stubbed response. `match` decides if this route handles a request;
    /// `respond` returns the response, body, and any redirect/error to emit.
    struct Route {
        let match: @Sendable (URLRequest) -> Bool
        let kind: Kind
        let onHit: (@Sendable () -> Void)?

        enum Kind {
            case response(status: Int, headers: [String: String], body: Data)
            case redirect(status: Int, location: String)
            case failure(error: URLError)
        }

        static func ok(
            path: String,
            body: Data,
            onHit: (@Sendable () -> Void)? = nil
        )
            -> Self
        {
            // Suffix match so `/api/organizations` never also matches
            // `/api/organizations/{uuid}/usage` (the org list vs the usage
            // endpoint share a prefix).
            Self(
                match: { ($0.url?.path).map { $0.hasSuffix(path) } ?? false },
                kind: .response(
                    status: 200,
                    headers: ["Content-Type": "application/json"],
                    body: body
                ),
                onHit: onHit
            )
        }

        static func ok(
            path: String,
            headers: [String: String],
            body: Data
        )
            -> Self
        {
            var merged = headers
            merged["Content-Type"] = merged["Content-Type"] ?? "application/json"
            return Self(
                match: { ($0.url?.path).map { $0.hasSuffix(path) } ?? false },
                kind: .response(status: 200, headers: merged, body: body),
                onHit: nil
            )
        }

        static func ok(
            path: String,
            matchHost: Bool,
            body: Data
        )
            -> Self
        {
            Self(
                match: { request in
                    if matchHost {
                        return (request.url?.host).map { $0.contains(path) } ?? false
                    }
                    return (request.url?.path).map { $0.contains(path) } ?? false
                },
                kind: .response(
                    status: 200,
                    headers: ["Content-Type": "application/json"],
                    body: body
                ),
                onHit: nil
            )
        }

        static func html(path: String, status: Int, body: String) -> Self {
            Self(
                match: { ($0.url?.path).map { $0.hasSuffix(path) } ?? false },
                kind: .response(
                    status: status,
                    headers: ["Content-Type": "text/html; charset=utf-8"],
                    body: Data(body.utf8)
                ),
                onHit: nil
            )
        }

        static func redirect(path: String, status: Int, location: String) -> Self {
            Self(
                match: { ($0.url?.path).map { $0.hasSuffix(path) } ?? false },
                kind: .redirect(status: status, location: location),
                onHit: nil
            )
        }

        static func failure(path: String, error: URLError) -> Self {
            Self(
                match: { ($0.url?.path).map { $0.hasSuffix(path) } ?? false },
                kind: .failure(error: error),
                onHit: nil
            )
        }
    }

    // MARK: - Shared state (lock-guarded)

    private static let lock = NSLock()
    // Modifier order set by SwiftFormat's `modifierOrder`; SwiftLint's
    // `modifier_order` disagrees, so suppress it here (SwiftFormat is the
    // formatting source of truth).
    // swiftlint:disable modifier_order
    private nonisolated(unsafe) static var routes: [Route] = []
    private nonisolated(unsafe) static var recorded: [URLRequest] = []
    // swiftlint:enable modifier_order

    static func install(_ routes: [Route]) {
        lock.lock()
        defer { lock.unlock() }
        self.routes = routes
        recorded = []
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        routes = []
        recorded = []
    }

    static var recordedRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    private static func route(for request: URLRequest) -> Route? {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
        return routes.first { $0.match(request) }
    }

    // MARK: - URLProtocol

    // `class func` (not `static`): these override `URLProtocol` requirements.
    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    // swiftlint:enable static_over_final_class

    override func startLoading() {
        guard let client else { return }
        guard let route = Self.route(for: request) else {
            client.urlProtocol(
                self,
                didFailWithError: URLError(.unsupportedURL)
            )
            return
        }
        route.onHit?()

        // Inline `let` bindings are enforced by SwiftFormat (`--patternlet
        // inline`); SwiftLint's `pattern_matching_keywords` wants them hoisted,
        // so suppress it here.
        // swiftlint:disable pattern_matching_keywords
        switch route.kind {
        case .response(let status, let headers, let body):
            send(status: status, headers: headers, body: body, to: client)

        case .redirect(let status, let location):
            sendRedirect(status: status, location: location, to: client)

        case .failure(let error):
            client.urlProtocol(self, didFailWithError: error)
        }
        // swiftlint:enable pattern_matching_keywords
    }

    override func stopLoading() {}

    // MARK: - Helpers

    private func send(
        status: Int,
        headers: [String: String],
        body: Data,
        to client: any URLProtocolClient
    ) {
        guard
            let url = request.url,
            let response = HTTPURLResponse(
                url: url, statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: headers
            )
        else {
            client.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: body)
        client.urlProtocolDidFinishLoading(self)
    }

    private func sendRedirect(
        status: Int,
        location: String,
        to client: any URLProtocolClient
    ) {
        guard
            let url = request.url,
            let target = URL(string: location),
            let response = HTTPURLResponse(
                url: url, statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": location]
            )
        else {
            client.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        var redirected = URLRequest(url: target)
        // Carry the original request's headers forward so the redirect delegate
        // under test sees the Cookie header it must strip when going off-host.
        redirected.allHTTPHeaderFields = request.allHTTPHeaderFields
        client.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
    }
}
