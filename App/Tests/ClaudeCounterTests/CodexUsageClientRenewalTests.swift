import Foundation
import Testing
@testable import ClaudeCounter

// MARK: - Codex 401 renewal

/// Lives in the serialized `UsageAPIClientTests` suite because
/// `StubURLProtocol`'s routes are process-global.
extension UsageAPIClientTests {
    private func codexAuthFile() throws -> (CodexAuthStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-renewal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("auth.json")
        try #"{"tokens":{"access_token":"a.b.c","account_id":"acct"}}"#
            .write(to: file, atomically: true, encoding: .utf8)
        return (CodexAuthStore(path: file), dir)
    }

    private func codexClient(
        status firstStatus: Int,
        renewal: @escaping @Sendable () async -> Bool
    ) throws
        -> (CodexUsageClient, URL)
    {
        let (auth, dir) = try codexAuthFile()
        let usage = try UsageAPIClientFixtures.data("codex_usage_both_windows")
        let served = HitCounter()
        let isFirstRequest: @Sendable (URLRequest) -> Bool = { _ in served.value == 0 }
        StubURLProtocol.install([
            StubURLProtocol.Route(
                match: isFirstRequest,
                kind: .response(status: firstStatus, headers: [:], body: Data())
            ) { served.bump() },
            .ok(path: "/wham/usage", body: usage)
        ])
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return (CodexUsageClient(configuration: config, auth: auth, renewLogin: renewal), dir)
    }

    private func reauthReason(_ result: CodexFetchResult) -> CodexReauthReason? {
        guard case .needsReauth(let reason) = result else { return nil }
        return reason
    }

    @Test func codex_401_renews_the_login_and_retries() async throws {
        let renewals = HitCounter()
        let (client, dir) = try codexClient(status: 401) {
            renewals.bump()
            return true
        }
        defer {
            StubURLProtocol.reset()
            try? FileManager.default.removeItem(at: dir)
        }

        guard case .success = await client.fetch() else {
            Issue.record("expected success after renewal")
            return
        }
        #expect(renewals.value == 1)
    }

    @Test func codex_401_without_a_renewal_still_asks_for_login() async throws {
        let (client, dir) = try codexClient(status: 401) { false }
        defer {
            StubURLProtocol.reset()
            try? FileManager.default.removeItem(at: dir)
        }
        #expect(await reauthReason(client.fetch()) == .rejected(status: 401, tokenExpired: false))
    }

    @Test func codex_403_is_not_a_reason_to_renew() async throws {
        let renewals = HitCounter()
        let (client, dir) = try codexClient(status: 403) {
            renewals.bump()
            return true
        }
        defer {
            StubURLProtocol.reset()
            try? FileManager.default.removeItem(at: dir)
        }
        #expect(await reauthReason(client.fetch()) == .rejected(status: 403, tokenExpired: false))
        #expect(renewals.value == 0)
    }
}
