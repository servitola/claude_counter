import Foundation
import Testing
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
        #expect(claudeUsage.currentPercent == 3)
        #expect(claudeUsage.weeklyPercent == 51)
        #expect(claudeUsage.currentResetAt != nil)
        #expect(claudeUsage.weeklyResetAt != nil)
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

    @Test func multiOrgPicksActiveOrFirst() async throws {
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
