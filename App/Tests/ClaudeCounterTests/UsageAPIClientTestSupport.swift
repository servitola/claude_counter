import Foundation
import Testing
@testable import ClaudeCounter

// MARK: - UsageAPIClientTests

/// Single suite for every `UsageAPIClient.fetch()` test. The cases are split
/// across files via extensions (core in `UsageAPIClientTests.swift`,
/// classification in `UsageAPIClientClassificationTests.swift`) so no one file
/// grows past the length limit, yet they all share ONE serialized suite.
///
/// `.serialized` is mandatory: `StubURLProtocol`'s route table is process-global
/// shared state. Splitting into multiple suites would let them run concurrently
/// and stomp on each other's routes, so a single suite is the only safe shape.
@Suite(.serialized)
struct UsageAPIClientTests {}

// MARK: - IsolatedStore

/// An `OrgIDStore` over a throwaway `UserDefaults` suite so tests never touch
/// the shared app defaults or bleed into each other. `tearDown()` removes the
/// suite; call it from a `defer`.
struct IsolatedStore {
    let store: OrgIDStore
    private let defaults: UserDefaults
    private let suiteName: String

    init() throws {
        self.suiteName = "UsageAPIClientTests.\(UUID().uuidString)"
        self.defaults = try #require(UserDefaults(suiteName: suiteName))
        self.store = OrgIDStore(defaults: defaults)
    }

    func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

// MARK: - UsageAPIClientFixtures

enum UsageAPIClientFixtures {
    static func data(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json"),
            "Missing fixture \(name).json in test bundle"
        )
        return try Data(contentsOf: url)
    }

    /// Parse an ISO-8601 timestamp with fractional seconds, mirroring the
    /// decoder under test so tests can assert EXACT reset Dates.
    static func iso(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: string) else {
            fatalError("invalid ISO-8601 fixture timestamp: \(string)")
        }
        return date
    }

    /// Two-org inline fixture: first org inactive; pick must be deterministic.
    static let twoOrgJSON = """
    [
      { "uuid": "00000000-0000-4000-8000-0000000000AA" },
      { "uuid": "00000000-0000-4000-8000-0000000000BB" }
    ]
    """

    static let challengeHTML = """
    <!DOCTYPE html><html><head><title>Just a moment...</title></head>
    <body>Checking your browser before accessing claude.ai.</body></html>
    """

    static let loginHTML = """
    <!DOCTYPE html><html><head><title>Log in to Claude</title></head>
    <body><form action="/login"><input name="email"></form></body></html>
    """
}

/// Builds a client wired to a path-routed stub and installs the routes.
/// `cookieHeader` is the outgoing Cookie value; captured Set-Cookie headers go
/// to `writeBack`.
func makeStubbedClient(
    routes: [StubURLProtocol.Route],
    store: OrgIDStore,
    cookieHeader: String = "sessionKey=test",
    writeBack: @escaping @Sendable ([String], URL) async -> Void = { _, _ in },
    log: @escaping @Sendable (String) -> Void = { _ in }
)
    -> UsageAPIClient
{
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    let cookies = CookieSource(header: { cookieHeader }, writeBack: writeBack)
    let client = UsageAPIClient(
        configuration: config,
        orgStore: store,
        cookies: cookies,
        log: log
    )
    StubURLProtocol.install(routes)
    return client
}

// MARK: - LogCollector

/// Thread-safe collector for emitted log lines.
final class LogCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        lines.append(line)
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}

// MARK: - HitCounter

/// Thread-safe counter for stub route hits.
final class HitCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func bump() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
