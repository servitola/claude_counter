import Foundation
import Testing
@testable import ClaudeCounter

struct UsageMapperTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Helpers

    private func fixtureResponse() throws -> UsageResponse {
        let url = try #require(
            Bundle.module.url(forResource: "usage", withExtension: "json"),
            "Missing fixture usage.json in test bundle"
        )
        let data = try Data(contentsOf: url)
        return try UsageAPIModels.decoder.decode(UsageResponse.self, from: data)
    }

    /// Reference date built independently of the decoder under test.
    private func isoDate(_ string: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try #require(formatter.date(from: string))
    }

    private func limit(kind: String, percent: Double, resetsAt: Date? = nil) -> UsageLimit {
        UsageLimit(group: "g", kind: kind, percent: percent, resetsAt: resetsAt, isActive: nil)
    }

    // MARK: - TDD anchors

    @Test func maps_session_to_current_and_weekly_all_to_weekly() throws {
        let response = try fixtureResponse()
        let usage = try #require(UsageMapper.map(response, now: now))

        #expect(usage.currentPercent == 3)
        #expect(usage.weeklyPercent == 51)
        #expect(usage.updatedAt == now)
    }

    @Test func maps_resets_at_to_exact_dates() throws {
        let response = try fixtureResponse()
        let usage = try #require(UsageMapper.map(response, now: now))

        // weekly must come from weekly_all (…900484), not weekly_scoped
        // (…900493) — the fixture's weekly_scoped percent is 8, so asserting
        // weeklyPercent == 51 already proves weekly_all was selected.
        let expectedCurrent = try isoDate("2026-06-17T13:49:59.900458+00:00")
        let expectedWeekly = try isoDate("2026-06-17T18:59:59.900484+00:00")

        #expect(usage.currentResetAt == expectedCurrent)
        #expect(usage.weeklyResetAt == expectedWeekly)
        #expect(usage.weeklyPercent == 51)
    }

    @Test func missing_weekly_all_falls_back_to_seven_day() throws {
        let sevenDayReset = try isoDate("2026-06-17T18:59:59.900484+00:00")
        let response = UsageResponse(
            limits: [limit(kind: "session", percent: 3, resetsAt: now)],
            fiveHour: nil,
            sevenDay: FlatWindow(resetsAt: sevenDayReset, utilization: 51)
        )

        let usage = try #require(UsageMapper.map(response, now: now))
        #expect(usage.weeklyPercent == 51)
        #expect(usage.weeklyResetAt == sevenDayReset)
    }

    @Test func missing_session_falls_back_to_five_hour() throws {
        let fiveHourReset = try isoDate("2026-06-17T13:49:59.900458+00:00")
        let response = UsageResponse(
            limits: [limit(kind: "weekly_all", percent: 51, resetsAt: now)],
            fiveHour: FlatWindow(resetsAt: fiveHourReset, utilization: 7),
            sevenDay: nil
        )

        let usage = try #require(UsageMapper.map(response, now: now))
        #expect(usage.currentPercent == 7)
        #expect(usage.currentResetAt == fiveHourReset)
    }

    @Test func nil_resets_at_passes_through_without_failing_map() throws {
        let response = UsageResponse(
            limits: [limit(kind: "session", percent: 3, resetsAt: nil)],
            fiveHour: nil,
            sevenDay: nil
        )

        let usage = try #require(UsageMapper.map(response, now: now))
        #expect(usage.currentPercent == 3)
        #expect(usage.currentResetAt == nil)
    }

    @Test func percent_double_truncates_to_int() throws {
        let response = UsageResponse(
            limits: [limit(kind: "session", percent: 2.9, resetsAt: now)],
            fiveHour: nil,
            sevenDay: nil
        )

        let usage = try #require(UsageMapper.map(response, now: now))
        #expect(usage.currentPercent == 2)
    }

    @Test func empty_limits_no_flat_fields_returns_nil() {
        let response = UsageResponse(limits: [], fiveHour: nil, sevenDay: nil)
        #expect(UsageMapper.map(response, now: now) == nil)
    }
}
