import Foundation
import Testing
@testable import ClaudeCounter

struct CodexUsageMapperTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func fixture(_ name: String) throws -> CodexUsageResponse {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json"),
            "Missing fixture \(name).json in test bundle"
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CodexUsageResponse.self, from: data)
    }

    // MARK: - Duration-based classification

    /// Both windows present: the 5h (18000s) window feeds `current`, the weekly
    /// (604800s) window feeds `weekly` — regardless of the primary/secondary label.
    @Test func maps_both_windows_by_duration() throws {
        let usage = try #require(CodexUsageMapper.map(
            fixture("codex_usage_both_windows"),
            now: now
        ))

        #expect(usage.currentPercent == 42)
        #expect(usage.weeklyPercent == 7)
        #expect(usage.currentResetAt == Date(timeIntervalSince1970: 1_785_332_773))
        #expect(usage.weeklyResetAt == Date(timeIntervalSince1970: 1_785_900_000))
    }

    /// The real Plus-account shape: the sole window arrives as `primary_window`
    /// with a 7-day duration and `secondary_window: null`. It must map to WEEKLY,
    /// not current — the naive "primary == 5h" mapping would be wrong.
    @Test func primary_window_with_weekly_duration_maps_to_weekly() throws {
        let usage = try #require(CodexUsageMapper.map(fixture("codex_usage_weekly_only"), now: now))

        #expect(usage.currentPercent == nil)
        #expect(usage.currentResetAt == nil)
        #expect(usage.weeklyPercent == 0)
        #expect(usage.weeklyResetAt == Date(timeIntervalSince1970: 1_785_332_773))
    }

    // MARK: - Edge cases

    @Test func nil_rate_limit_maps_to_nil() {
        let response = CodexUsageResponse(rateLimit: nil)
        #expect(CodexUsageMapper.map(response, now: now) == nil)
    }

    @Test func reset_after_seconds_used_when_no_epoch() {
        let window = CodexUsageResponse.Window(
            usedPercent: 10, limitWindowSeconds: 18000, resetAfterSeconds: 600, resetAt: nil
        )
        let response = CodexUsageResponse(
            rateLimit: .init(primaryWindow: window, secondaryWindow: nil)
        )
        let usage = CodexUsageMapper.map(response, now: now)
        #expect(usage?.currentPercent == 10)
        #expect(usage?.currentResetAt == now.addingTimeInterval(600))
    }
}
