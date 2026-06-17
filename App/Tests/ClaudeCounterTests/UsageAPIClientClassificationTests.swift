import Foundation
import Testing
@testable import ClaudeCounter

// MARK: - Response-classification tests

/// Classification cases for `UsageAPIClient.fetch()`. The org uuid is pre-seeded
/// so each test exercises only the `/usage` classification path. Part of the
/// single serialized `UsageAPIClientTests` suite (declared in the support file).
extension UsageAPIClientTests {
    private static let seededUUID = "00000000-0000-4000-8000-000000000001"

    /// Seeds the uuid and builds a client whose only route is `/usage`.
    private func usageClient(
        _ route: StubURLProtocol.Route,
        store: OrgIDStore
    )
        -> UsageAPIClient
    {
        store.write(Self.seededUUID)
        return makeStubbedClient(routes: [route], store: store)
    }

    @Test func challengeHTMLReturnsNeedsCookieRefresh() async throws {
        let isolated = try IsolatedStore()
        defer { isolated.tearDown() }
        let client = usageClient(
            .html(path: "/usage", status: 403, body: UsageAPIClientFixtures.challengeHTML),
            store: isolated.store
        )
        defer { StubURLProtocol.reset() }

        let result = await client.fetch()
        guard case .needsCookieRefresh = result else {
            Issue.record("Expected .needsCookieRefresh, got \(result)")
            return
        }
    }

    @Test func loginPageBodyReturnsNotLoggedIn() async throws {
        let isolated = try IsolatedStore()
        defer { isolated.tearDown() }
        // A 200 whose body is the login page must classify BEFORE JSON decode.
        let client = usageClient(
            .html(path: "/usage", status: 200, body: UsageAPIClientFixtures.loginHTML),
            store: isolated.store
        )
        defer { StubURLProtocol.reset() }

        let result = await client.fetch()
        guard case .notLoggedIn = result else {
            Issue.record("Expected .notLoggedIn, got \(result)")
            return
        }
    }

    @Test func status401ReturnsNotLoggedIn() async throws {
        let isolated = try IsolatedStore()
        defer { isolated.tearDown() }
        let client = usageClient(
            .html(path: "/usage", status: 401, body: "{}"),
            store: isolated.store
        )
        defer { StubURLProtocol.reset() }

        let result = await client.fetch()
        guard case .notLoggedIn = result else {
            Issue.record("Expected .notLoggedIn, got \(result)")
            return
        }
    }

    @Test func loginRedirectReturnsNotLoggedIn() async throws {
        let isolated = try IsolatedStore()
        defer { isolated.tearDown() }
        // A redirect to /login on the same host signals an expired session.
        let client = makeStubbedClient(
            routes: [
                .redirect(path: "/usage", status: 302, location: "https://claude.ai/login"),
                .html(path: "/login", status: 200, body: UsageAPIClientFixtures.loginHTML)
            ],
            store: isolated.store
        )
        isolated.store.write(Self.seededUUID)
        defer { StubURLProtocol.reset() }

        let result = await client.fetch()
        guard case .notLoggedIn = result else {
            Issue.record("Expected .notLoggedIn, got \(result)")
            return
        }
    }

    @Test func garbageJSONReturnsDecodeFailed() async throws {
        let isolated = try IsolatedStore()
        defer { isolated.tearDown() }
        // Valid JSON, but no limits and no flat windows → unmappable.
        let client = usageClient(
            .ok(path: "/usage", body: Data(#"{"unexpected":true}"#.utf8)),
            store: isolated.store
        )
        defer { StubURLProtocol.reset() }

        let result = await client.fetch()
        guard case .decodeFailed = result else {
            Issue.record("Expected .decodeFailed, got \(result)")
            return
        }
    }
}
