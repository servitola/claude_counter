import Foundation
import Testing
import WebKit
@testable import ClaudeCounter

// MARK: - Core fetch / discovery / transport / redirect / log tests

/// Classification cases live in `UsageAPIClientClassificationTests.swift`. All
/// tests are `URLProtocol`-stubbed and deterministic — no live network. The
/// suite is declared (and `.serialized`) in `UsageAPIClientTestSupport.swift`.
extension UsageAPIClientTests {
    // MARK: - Success

    @Test func successReturnsPopulatedUsage() async throws {
        let isolated = try IsolatedStore()
        defer { isolated.tearDown() }

        let orgs = try UsageAPIClientFixtures.data("organizations")
        let usage = try UsageAPIClientFixtures.data("usage")
        let client = makeStubbedClient(
            routes: [
                .ok(path: "/api/organizations", body: orgs),
                .ok(path: "/usage", body: usage)
            ],
            store: isolated.store
        )
        defer { StubURLProtocol.reset() }

        let result = await client.fetch()
        guard case .success(let claudeUsage) = result else {
            Issue.record("Expected .success, got \(result)")
            return
        }
        // Exact values from usage.json: a current/weekly swap or a
        // weekly_all-vs-weekly_scoped mismap would change these.
        #expect(claudeUsage.currentPercent == 3)
        #expect(claudeUsage.weeklyPercent == 51)
        #expect(claudeUsage.currentResetAt == UsageAPIClientFixtures
            .iso("2026-06-17T13:49:59.900458+00:00"))
        #expect(claudeUsage.weeklyResetAt == UsageAPIClientFixtures
            .iso("2026-06-17T18:59:59.900484+00:00"))
    }

    // MARK: - Cookie write-back (end to end)

    /// A 200 `/usage` carrying a rotating `Set-Cookie` for claude.ai must land
    /// in the WebView cookie store via the real `CookieBridge`. Litmus: removing
    /// the `writeBackCookies` call in `UsageAPIClient` breaks this test.
    @MainActor
    @Test func successWritesRotatingCookieBackToStore() async throws {
        let isolated = try IsolatedStore()
        defer { isolated.tearDown() }

        let webStore = WKWebsiteDataStore.nonPersistent()
        let bridge = CookieBridge(store: webStore)

        let orgs = try UsageAPIClientFixtures.data("organizations")
        let usage = try UsageAPIClientFixtures.data("usage")
        let client = makeStubbedClient(
            routes: [
                .ok(path: "/api/organizations", body: orgs),
                .ok(
                    path: "/usage",
                    headers: [
                        "Set-Cookie":
                            "__cf_bm=rotated-from-api; Path=/; Domain=claude.ai; "
                            + "Expires=Wed, 09 Jun 2027 10:18:14 GMT; Secure; HttpOnly"
                    ],
                    body: usage
                )
            ],
            store: isolated.store,
            // swiftlint:disable:next trailing_closure
            writeBack: { headers, url in
                await bridge.writeBack(setCookieHeaders: headers, responseURL: url)
            }
        )
        defer { StubURLProtocol.reset() }

        let result = await client.fetch()
        guard case .success = result else {
            Issue.record("Expected .success, got \(result)")
            return
        }

        let cookies = await webStore.httpCookieStore.allCookies()
        let match = cookies.first { $0.name == "__cf_bm" }
        #expect(match?.value == "rotated-from-api")
        // Secure/HttpOnly survive because the raw Set-Cookie is forwarded
        // without lossy name=value;Domain;Path reconstruction.
        #expect(match?.isSecure == true)
        #expect(match?.isHTTPOnly == true)
    }

    // MARK: - Discovery / caching

    @Test func discoveryCachesUUID() async throws {
        let isolated = try IsolatedStore()
        defer { isolated.tearDown() }

        let orgs = try UsageAPIClientFixtures.data("organizations")
        let usage = try UsageAPIClientFixtures.data("usage")
        let counter = HitCounter()
        let client = makeStubbedClient(
            routes: [
                .ok(path: "/api/organizations", body: orgs) { counter.bump() },
                .ok(path: "/usage", body: usage)
            ],
            store: isolated.store
        )
        defer { StubURLProtocol.reset() }

        _ = await client.fetch()
        #expect(isolated.store.read() == "00000000-0000-4000-8000-000000000001")
        #expect(counter.value == 1)

        // Second fetch must reuse the cached uuid — no /organizations request.
        _ = await client.fetch()
        #expect(counter.value == 1)
    }

    @Test func multiOrgPicksFirst() async throws {
        let isolated = try IsolatedStore()
        defer { isolated.tearDown() }

        let usage = try UsageAPIClientFixtures.data("usage")
        let client = makeStubbedClient(
            routes: [
                .ok(
                    path: "/api/organizations",
                    body: Data(UsageAPIClientFixtures.twoOrgJSON.utf8)
                ),
                .ok(path: "/usage", body: usage)
            ],
            store: isolated.store
        )
        defer { StubURLProtocol.reset() }

        let result = await client.fetch()
        guard case .success = result else {
            Issue.record("Expected .success, got \(result)")
            return
        }
        // First uuid is the deterministic pick when no active flag is present.
        #expect(isolated.store.read() == "00000000-0000-4000-8000-0000000000AA")
    }

    // MARK: - UUID guard

    /// A discovered org "uuid" that is not a well-formed UUID must fail
    /// discovery (and invalidate the cache) rather than be interpolated raw
    /// into the `/usage` path.
    @Test func nonUUIDOrgFailsDiscovery() async throws {
        let isolated = try IsolatedStore()
        defer { isolated.tearDown() }

        let usage = try UsageAPIClientFixtures.data("usage")
        let malicious = #"[{ "uuid": "../../etc/passwd" }]"#
        let client = makeStubbedClient(
            routes: [
                .ok(path: "/api/organizations", body: Data(malicious.utf8)),
                .ok(path: "/usage", body: usage)
            ],
            store: isolated.store
        )
        defer { StubURLProtocol.reset() }

        let result = await client.fetch()
        guard case .decodeFailed = result else {
            Issue.record("Expected .decodeFailed, got \(result)")
            return
        }
        // Cache must be invalidated so the next tick re-discovers.
        #expect(isolated.store.read() == nil)
    }

    // MARK: - Transport

    @Test func transportErrorReturnsTransport() async throws {
        let isolated = try IsolatedStore()
        defer { isolated.tearDown() }
        isolated.store.write("00000000-0000-4000-8000-000000000001")

        let client = makeStubbedClient(
            routes: [.failure(path: "/usage", error: URLError(.notConnectedToInternet))],
            store: isolated.store
        )
        defer { StubURLProtocol.reset() }

        let result = await client.fetch()
        guard case .transport = result else {
            Issue.record("Expected .transport, got \(result)")
            return
        }
    }

    // MARK: - Off-host redirect

    @Test func offHostRedirectStripsCookie() async throws {
        let isolated = try IsolatedStore()
        defer { isolated.tearDown() }
        isolated.store.write("00000000-0000-4000-8000-000000000001")

        let sentinel = "sessionKey=SENTINEL-do-not-leak"
        let evilHost = "https://evil.example.com/usage"
        let client = makeStubbedClient(
            routes: [
                .redirect(path: "/usage", status: 302, location: evilHost),
                .ok(path: "evil.example.com", matchHost: true, body: Data("{}".utf8))
            ],
            store: isolated.store,
            cookieHeader: sentinel
        )
        defer { StubURLProtocol.reset() }

        _ = await client.fetch()

        // The request that reached the off-host target must carry no Cookie.
        let offHost = StubURLProtocol.recordedRequests.first { $0.url?.host == "evil.example.com" }
        let request = try #require(offHost, "off-host request was never made")
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }

    // MARK: - Log discipline (Decision 6)

    @Test func noCookieValueInLogs() async throws {
        let isolated = try IsolatedStore()
        defer { isolated.tearDown() }

        let sentinel = "S3CR3T-cookie-sentinel"
        let sink = LogCollector()
        let orgs = try UsageAPIClientFixtures.data("organizations")
        let usage = try UsageAPIClientFixtures.data("usage")
        let client = makeStubbedClient(
            routes: [
                .ok(path: "/api/organizations", body: orgs),
                .ok(path: "/usage", body: usage)
            ],
            store: isolated.store,
            cookieHeader: "sessionKey=\(sentinel)",
            // swiftlint:disable:next trailing_closure
            log: { line in sink.append(line) }
        )
        defer { StubURLProtocol.reset() }

        _ = await client.fetch()

        let lines = sink.snapshot()
        #expect(!lines.isEmpty)
        for line in lines {
            #expect(!line.contains(sentinel))
        }
    }
}
