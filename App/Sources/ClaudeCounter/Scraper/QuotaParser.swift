import Foundation

/// Pure conversion from `QuotaPayload` (raw scrape) to `ClaudeUsage`
/// (domain model). Deterministic and Sendable: testable without WebKit.
enum QuotaParser {
    /// `now` is parameterised so tests can pin time and assert
    /// `currentResetAt` deterministically.
    static func parse(_ payload: QuotaPayload, now: Date = Date()) -> ClaudeUsage? {
        guard payload.found else { return nil }
        let current = payload.textPercents.first ?? payload.barPercents.first
        let weekly = secondElement(payload.textPercents) ?? secondElement(payload.barPercents)
        let resetAt = payload.resetMinutes.map { now.addingTimeInterval(TimeInterval($0 * 60)) }
        let weeklyResetAt = payload.weeklyResetMinutes
            .map { now.addingTimeInterval(TimeInterval($0 * 60)) }
        return ClaudeUsage(
            currentPercent: current.map { Int($0) },
            weeklyPercent: weekly.map { Int($0) },
            currentResetAt: resetAt,
            weeklyResetAt: weeklyResetAt,
            updatedAt: now
        )
    }

    private static func secondElement(_ array: [Double]) -> Double? {
        array.count > 1 ? array[1] : nil
    }
}
