import Foundation

/// Pure conversion from a decoded `UsageResponse` (API path) to
/// `ClaudeUsage` (domain model). Counterpart to `QuotaParser` (DOM-scrape
/// path): deterministic and Sendable, with `now` injected so tests can pin
/// time. This is the single place that decides which `limits[]` entry feeds
/// the current vs weekly numbers (canonical source is `limits[]`; the flat
/// top-level windows are the fallback).
enum UsageMapper {
    /// Maps `response` to `ClaudeUsage`. Returns `nil` only when neither a
    /// usable `limits[]` entry nor a flat fallback yields a current OR weekly
    /// value, so the caller can surface `.decodeFailed`.
    ///
    /// `now` is parameterised to set `updatedAt` and to let tests pin time.
    static func map(_ response: UsageResponse, now: Date = Date()) -> ClaudeUsage? {
        // Current ← limits[kind == "session"], else flat five_hour.
        let session = response.limits.first { $0.kind == "session" }
        // Weekly ← limits[kind == "weekly_all"] strictly; weekly_scoped is
        // never selected. Else flat seven_day.
        let weeklyAll = response.limits.first { $0.kind == "weekly_all" }

        let currentPercent = session.map { Int($0.percent) }
            ?? response.fiveHour.map { Int($0.utilization) }
        let currentResetAt = session?.resetsAt ?? response.fiveHour?.resetsAt

        let weeklyPercent = weeklyAll.map { Int($0.percent) }
            ?? response.sevenDay.map { Int($0.utilization) }
        let weeklyResetAt = weeklyAll?.resetsAt ?? response.sevenDay?.resetsAt

        guard currentPercent != nil || weeklyPercent != nil else { return nil }

        return ClaudeUsage(
            currentPercent: currentPercent,
            weeklyPercent: weeklyPercent,
            currentResetAt: currentResetAt,
            weeklyResetAt: weeklyResetAt,
            updatedAt: now
        )
    }
}
