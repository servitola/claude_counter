import Foundation
import Testing
@testable import ClaudeCounter

struct StatusExportTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Decode the exported JSON back into a loosely-typed dictionary so the
    /// assertions read against the on-disk contract, not the Swift model.
    private func object(_ data: Data) throws -> [String: Any] {
        let json = try JSONSerialization.jsonObject(with: data)
        return try #require(json as? [String: Any])
    }

    private func isoDate(_ string: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try #require(formatter.date(from: string))
    }

    // MARK: - Field contract

    @Test func encodes_all_fields_when_present() throws {
        let usage = try ClaudeUsage(
            currentPercent: 9,
            weeklyPercent: 26,
            currentResetAt: isoDate("2026-07-14T15:30:00Z"),
            weeklyResetAt: isoDate("2026-07-20T00:00:00Z"),
            updatedAt: now
        )
        let object = try object(StatusExport.encode(usage))

        #expect(object["schemaVersion"] as? Int == StatusExport.schemaVersion)
        #expect(object["currentPercent"] as? Int == 9)
        #expect(object["weeklyPercent"] as? Int == 26)
        #expect(object["currentResetAt"] as? String == "2026-07-14T15:30:00Z")
        #expect(object["weeklyResetAt"] as? String == "2026-07-20T00:00:00Z")
        #expect(object["updatedAt"] as? String == "2023-11-14T22:13:20Z")
    }

    @Test func omits_nil_fields_but_keeps_version_and_updatedAt() throws {
        let object = try object(StatusExport.encode(.empty, now: now))

        #expect(object["schemaVersion"] as? Int == StatusExport.schemaVersion)
        #expect(object["updatedAt"] as? String == "2023-11-14T22:13:20Z")
        #expect(object["currentPercent"] == nil)
        #expect(object["weeklyPercent"] == nil)
        #expect(object["currentResetAt"] == nil)
        #expect(object["weeklyResetAt"] == nil)
    }

    @Test func falls_back_to_now_when_snapshot_has_no_updatedAt() throws {
        var usage = ClaudeUsage.empty
        usage.currentPercent = 5
        let object = try object(StatusExport.encode(usage, now: now))

        #expect(object["updatedAt"] as? String == "2023-11-14T22:13:20Z")
    }

    // MARK: - Codex (schema v2)

    @Test func encodes_codex_object_when_present() throws {
        let codex = try ProviderUsage(
            currentPercent: 4,
            weeklyPercent: 30,
            currentResetAt: isoDate("2026-07-14T15:30:00Z"),
            weeklyResetAt: isoDate("2026-07-20T00:00:00Z"),
            updatedAt: now
        )
        let object = try object(StatusExport.encode(.empty, codex: codex, now: now))
        let codexObject = try #require(object["codex"] as? [String: Any])

        #expect(object["schemaVersion"] as? Int == 2)
        #expect(codexObject["currentPercent"] as? Int == 4)
        #expect(codexObject["weeklyPercent"] as? Int == 30)
        #expect(codexObject["currentResetAt"] as? String == "2026-07-14T15:30:00Z")
        #expect(codexObject["weeklyResetAt"] as? String == "2026-07-20T00:00:00Z")
    }

    @Test func codex_object_present_but_empty_when_no_codex_data() throws {
        let object = try object(StatusExport.encode(.empty, now: now))
        let codexObject = try #require(object["codex"] as? [String: Any])
        #expect(codexObject["currentPercent"] == nil)
        #expect(codexObject["weeklyPercent"] == nil)
    }

    // MARK: - Determinism

    @Test func output_is_byte_stable_for_equal_input() throws {
        let usage = ClaudeUsage(
            currentPercent: 9, weeklyPercent: 26,
            currentResetAt: now, weeklyResetAt: now, updatedAt: now
        )
        let first = try StatusExport.encode(usage)
        let second = try StatusExport.encode(usage)

        #expect(first == second)
    }

    // MARK: - stdout shape (the CLI writes exactly this)

    @Test func trailing_newline_free_body_parses_as_json() throws {
        // The CLI appends its own newline; the encoded body itself must be a
        // single valid JSON object with no trailing separator.
        let data = try StatusExport.encode(.empty, now: now)
        let object = try object(data)
        #expect(object["schemaVersion"] as? Int == StatusExport.schemaVersion)
    }
}
