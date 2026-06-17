import Foundation
import Testing
@testable import ClaudeCounter

struct OrgIDStoreTests {
    /// Builds a store backed by an isolated suite, runs `body`, then tears the
    /// suite down so suites never accumulate or bleed between tests.
    private func withIsolatedStore(_ body: (OrgIDStore, String) throws -> Void) throws {
        let suiteName = "OrgIDStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(OrgIDStore(defaults: defaults), suiteName)
    }

    @Test func writeThenReadReturnsUUID() throws {
        try withIsolatedStore { store, _ in
            let uuid = UUID().uuidString
            store.write(uuid)
            #expect(store.read() == uuid)
        }
    }

    @Test func invalidateClearsUUID() throws {
        try withIsolatedStore { store, _ in
            store.write(UUID().uuidString)
            store.invalidate()
            #expect(store.read() == nil)
        }
    }

    @Test func usesInjectedSuiteNotStandard() throws {
        try withIsolatedStore { store, _ in
            let uuid = UUID().uuidString
            store.write(uuid)
            // The write must land only in the injected suite, never in the
            // shared app defaults.
            #expect(UserDefaults.standard.string(forKey: OrgIDStore.key) == nil)
            #expect(store.read() == uuid)
        }
    }
}
