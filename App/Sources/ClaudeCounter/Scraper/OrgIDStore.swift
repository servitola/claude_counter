import Foundation

/// Sole owner of the cached claude.ai organization UUID, persisted in
/// `UserDefaults` under one well-known key. The backing store is injected so
/// production uses `.standard` while tests run against an isolated suite,
/// avoiding shared-state bleed. `UserDefaults` is thread-safe but not marked
/// `Sendable` by Foundation, so the type is `@unchecked Sendable`.
struct OrgIDStore: @unchecked Sendable {
    /// Well-known key for the cached org UUID, namespaced to the app.
    static let key = "org.uuid"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The currently cached org UUID, or `nil` when none has been stored.
    func read() -> String? {
        defaults.string(forKey: Self.key)
    }

    /// Store a freshly discovered org UUID, replacing any previous value.
    func write(_ uuid: String) {
        defaults.set(uuid, forKey: Self.key)
    }

    /// Clear the cached UUID. No-op when nothing is cached.
    func invalidate() {
        defaults.removeObject(forKey: Self.key)
    }
}
