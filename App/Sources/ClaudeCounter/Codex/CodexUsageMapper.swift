import Foundation

/// Pure conversion from a decoded `CodexUsageResponse` to `ProviderUsage`.
/// Counterpart to `UsageMapper` (Claude). Classifies each present window by its
/// duration (`limitWindowSeconds`): ~5h → current, longer (weekly/7d) → weekly.
/// Reset times come from `resetAt` (Unix epoch), falling back to
/// `resetAfterSeconds` relative to `now`.
enum CodexUsageMapper {
    /// Windows at or below this many seconds count as the short ("current")
    /// window; longer ones are the weekly window. 6h guards the nominal 5h
    /// window against small backend rounding.
    static let shortWindowMaxSeconds = 6 * 3600

    static func map(_ response: CodexUsageResponse, now: Date = Date()) -> ProviderUsage? {
        guard let rateLimit = response.rateLimit else { return nil }

        var windows = [rateLimit.primaryWindow, rateLimit.secondaryWindow]
            .compactMap(\.self)
        windows += rateLimit.additionalRateLimits
        guard !windows.isEmpty else { return nil }

        var currentPercent: Int?
        var currentResetAt: Date?
        var weeklyPercent: Int?
        var weeklyResetAt: Date?

        for window in windows {
            let percent = window.usedPercent.map { Int($0.rounded()) }
            let reset = resetDate(window, now: now)
            let isShort = (window.limitWindowSeconds ?? .max) <= shortWindowMaxSeconds
            if isShort {
                // First short window wins (deterministic if several are present).
                if currentPercent == nil {
                    currentPercent = percent
                    currentResetAt = reset
                }
            } else if weeklyPercent == nil {
                weeklyPercent = percent
                weeklyResetAt = reset
            }
        }

        guard currentPercent != nil || weeklyPercent != nil else { return nil }
        return ProviderUsage(
            currentPercent: currentPercent,
            weeklyPercent: weeklyPercent,
            currentResetAt: currentResetAt,
            weeklyResetAt: weeklyResetAt,
            updatedAt: now
        )
    }

    private static func resetDate(_ window: CodexUsageResponse.Window, now: Date) -> Date? {
        if let epoch = window.resetAt, epoch > 0 {
            return Date(timeIntervalSince1970: epoch)
        }
        if let after = window.resetAfterSeconds {
            return now.addingTimeInterval(TimeInterval(after))
        }
        return nil
    }
}
