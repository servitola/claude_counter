import Foundation
import Testing
@testable import ClaudeCounter

struct UsageAPIModelsTests {
    // MARK: - Helpers

    private func fixtureData(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json"),
            "Missing fixture \(name).json in test bundle"
        )
        return try Data(contentsOf: url)
    }

    /// Reference dates built with a fractional-seconds ISO-8601 formatter so
    /// expectations are independent of the decoder under test.
    private func isoDate(_ string: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try #require(formatter.date(from: string))
    }

    /// Reference date for a timestamp without fractional seconds.
    private func isoDateNoFractional(_ string: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try #require(formatter.date(from: string))
    }

    // MARK: - usage.json limits

    @Test func decodesUsageFixtureLimits() throws {
        let data = try fixtureData("usage")
        let response = try UsageAPIModels.decoder.decode(UsageResponse.self, from: data)

        #expect(response.limits.count == 3)

        let expectedSessionReset = try isoDate("2026-06-17T13:49:59.900458+00:00")
        let session = try #require(response.limits.first { $0.kind == "session" })
        #expect(session.percent == 3.0)
        #expect(session.group == "session")
        #expect(session.isActive == false)
        #expect(session.resetsAt == expectedSessionReset)

        let weeklyAll = try #require(response.limits.first { $0.kind == "weekly_all" })
        #expect(weeklyAll.percent == 51.0)
        #expect(weeklyAll.isActive == true)

        let weeklyScoped = try #require(response.limits.first { $0.kind == "weekly_scoped" })
        #expect(weeklyScoped.percent == 8.0)
    }

    // MARK: - usage.json flat windows

    @Test func decodesUsageFixtureFlatWindows() throws {
        let data = try fixtureData("usage")
        let response = try UsageAPIModels.decoder.decode(UsageResponse.self, from: data)

        let expectedFiveHourReset = try isoDate("2026-06-17T13:49:59.900458+00:00")
        let expectedSevenDayReset = try isoDate("2026-06-17T18:59:59.900484+00:00")
        #expect(response.fiveHour?.utilization == 3.0)
        #expect(response.sevenDay?.utilization == 51.0)
        #expect(response.fiveHour?.resetsAt == expectedFiveHourReset)
        #expect(response.sevenDay?.resetsAt == expectedSevenDayReset)
    }

    // MARK: - ISO-8601 two-formatter strategy

    @Test func decodesIsoDateWithAndWithoutFractionalSeconds() throws {
        let withFractional = try isoDate("2026-06-17T13:49:59.900458+00:00")
        let withoutFractional = try isoDateNoFractional("2026-06-17T13:49:59+00:00")

        let jsonWith = #"{"resets_at":"2026-06-17T13:49:59.900458+00:00","utilization":1}"#
        let jsonWithout = #"{"resets_at":"2026-06-17T13:49:59+00:00","utilization":1}"#

        let decodedWith = try UsageAPIModels.decoder.decode(
            FlatWindow.self, from: Data(jsonWith.utf8)
        )
        let decodedWithout = try UsageAPIModels.decoder.decode(
            FlatWindow.self, from: Data(jsonWithout.utf8)
        )

        #expect(decodedWith.resetsAt == withFractional)
        #expect(decodedWithout.resetsAt == withoutFractional)
    }

    // MARK: - organizations.json

    @Test func decodesOrganizationsFixtureUuid() throws {
        let data = try fixtureData("organizations")
        let orgs = try UsageAPIModels.decoder.decode([OrgSummary].self, from: data)

        #expect(orgs.first?.uuid == "00000000-0000-4000-8000-000000000001")
    }
}
