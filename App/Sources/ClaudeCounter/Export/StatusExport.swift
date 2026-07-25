import Foundation

/// Pure JSON serialization of a `ClaudeUsage` snapshot for third-party
/// consumers. Deterministic and `Sendable`: given the same `ClaudeUsage` it
/// always produces byte-identical output (sorted keys, pretty-printed,
/// ISO-8601 dates), so it is trivially testable and diff-stable on disk.
///
/// This is the public contract of the exported file. `schemaVersion` lets
/// consumers detect breaking changes; bump it whenever the field set or
/// semantics change. Nil percentages / reset dates are omitted (a key being
/// absent means "unknown", e.g. before the first successful fetch);
/// `schemaVersion` and `updatedAt` are always present.
enum StatusExport {
    /// Bump on any breaking change to the field set or semantics below.
    /// v2 adds the nested `codex` object; the top-level Claude fields are
    /// unchanged for back-compat.
    static let schemaVersion = 2

    /// Serializable view over both providers. Kept separate from the domain
    /// model so the on-disk contract can evolve independently of the internal
    /// types. The top-level `current*`/`weekly*` fields remain Claude (the
    /// original v1 contract); Codex lives under `codex`. Optional fields encode
    /// as absent when nil.
    private struct Payload: Encodable {
        let schemaVersion: Int
        let currentPercent: Int?
        let weeklyPercent: Int?
        let currentResetAt: Date?
        let weeklyResetAt: Date?
        let updatedAt: Date?
        let codex: ProviderPayload
    }

    /// Serializable view over one provider's windows (used for the nested
    /// `codex` object; a nil field encodes as absent).
    private struct ProviderPayload: Encodable {
        let currentPercent: Int?
        let weeklyPercent: Int?
        let currentResetAt: Date?
        let weeklyResetAt: Date?
        let updatedAt: Date?

        init(_ usage: ProviderUsage) {
            self.currentPercent = usage.currentPercent
            self.weeklyPercent = usage.weeklyPercent
            self.currentResetAt = usage.currentResetAt
            self.weeklyResetAt = usage.weeklyResetAt
            self.updatedAt = usage.updatedAt
        }
    }

    /// Encodes both snapshots to pretty-printed JSON `Data`. `now` supplies the
    /// top-level `updatedAt` when the Claude snapshot carries none (e.g.
    /// `.empty`), so a file is still meaningful before the first scrape; it is
    /// parameterised to let tests pin time. `codex` defaults to `.empty` so the
    /// existing single-argument call sites keep compiling.
    static func encode(
        _ usage: ClaudeUsage,
        codex: ProviderUsage = .empty,
        now: Date = Date()
    ) throws
        -> Data
    {
        let payload = Payload(
            schemaVersion: schemaVersion,
            currentPercent: usage.currentPercent,
            weeklyPercent: usage.weeklyPercent,
            currentResetAt: usage.currentResetAt,
            weeklyResetAt: usage.weeklyResetAt,
            updatedAt: usage.updatedAt ?? now,
            codex: ProviderPayload(codex)
        )
        return try encoder.encode(payload)
    }

    /// A fresh encoder per call: `JSONEncoder` is not `Sendable`. Sorted keys
    /// + pretty printing keep the file human-readable and byte-stable;
    /// `.iso8601` matches the format the API path already speaks.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
