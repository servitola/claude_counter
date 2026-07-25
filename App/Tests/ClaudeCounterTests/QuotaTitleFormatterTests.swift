import AppKit
import Testing
@testable import ClaudeCounter

@MainActor
struct QuotaTitleFormatterTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func emptyUsageRendersDashes() {
        let title = QuotaTitleFormatter.render(.empty, now: now)
        #expect(title.string == "  –% –m  –%")
    }

    @Test func bothPercentsRender() {
        let usage = ClaudeUsage(
            currentPercent: 12,
            weeklyPercent: 76,
            currentResetAt: now.addingTimeInterval(60 * 135),
            updatedAt: now
        )
        let title = QuotaTitleFormatter.render(usage, now: now)
        #expect(title.string == "  12% 2h 15m  76%")
    }

    @Test func weeklyOnlyOmitsFiveHourPlaceholder() {
        // Idle Codex: the API reports only a weekly window. The 5-hour slot
        // must be dropped entirely, not shown as "–% –m".
        let usage = ClaudeUsage(
            weeklyPercent: 0,
            weeklyResetAt: now.addingTimeInterval(60 * (60 * 24 * 6 + 60 * 7)),
            updatedAt: now
        )
        let title = QuotaTitleFormatter.render(usage, now: now)
        #expect(title.string == "  0% 6d 7h")
    }

    @Test func currentOnlyOmitsWeeklyPlaceholder() {
        let usage = ClaudeUsage(
            currentPercent: 11,
            currentResetAt: now.addingTimeInterval(60 * 141),
            updatedAt: now
        )
        let title = QuotaTitleFormatter.render(usage, now: now)
        #expect(title.string == "  11% 2h 21m")
    }

    @Test func weeklyResetTimeAppendsAfterPercent() {
        let usage = ClaudeUsage(
            currentPercent: 6,
            weeklyPercent: 32,
            currentResetAt: now.addingTimeInterval(60 * 271),
            weeklyResetAt: now.addingTimeInterval(60 * 551),
            updatedAt: now
        )
        let title = QuotaTitleFormatter.render(usage, now: now)
        #expect(title.string == "  6% 4h 31m  32% 9h 11m")
    }

    @Test func warnThresholdAtEightyTurnsOrange() {
        let usage = ClaudeUsage(
            currentPercent: QuotaTitleFormatter.warnThreshold,
            weeklyPercent: 50,
            currentResetAt: now.addingTimeInterval(60 * 30),
            updatedAt: now
        )
        let title = QuotaTitleFormatter.render(usage, now: now)
        let color = title.attribute(
            .foregroundColor, at: 2, effectiveRange: nil
        ) as? NSColor
        #expect(color == .systemOrange)
    }

    @Test func alertThresholdAtNinetyTurnsRed() {
        let usage = ClaudeUsage(
            currentPercent: QuotaTitleFormatter.alertThreshold,
            weeklyPercent: 50,
            currentResetAt: now.addingTimeInterval(60 * 30),
            updatedAt: now
        )
        let title = QuotaTitleFormatter.render(usage, now: now)
        let color = title.attribute(
            .foregroundColor, at: 2, effectiveRange: nil
        ) as? NSColor
        #expect(color == .systemRed)
    }

    @Test func belowWarnThresholdHasNoColor() {
        let usage = ClaudeUsage(
            currentPercent: QuotaTitleFormatter.warnThreshold - 1,
            weeklyPercent: 50,
            currentResetAt: now,
            updatedAt: now
        )
        let title = QuotaTitleFormatter.render(usage, now: now)
        let color = title.attribute(
            .foregroundColor, at: 2, effectiveRange: nil
        ) as? NSColor
        #expect(color == nil)
    }

    @Test(arguments: [
        (60 * 0, "0m"),
        (60 * 1, "1m"),
        (60 * 59, "59m"),
        (60 * 60, "1h"),
        (60 * 65, "1h 5m"),
        (60 * 135, "2h 15m"),
        (60 * 720, "12h"),
        (60 * 60 * 24, "1d"),
        (60 * (60 * 24 + 65), "1d 1h"),
        (60 * (60 * 24 * 4 + 60 * 2), "4d 2h"),
        (60 * (60 * 24 * 6 + 60 * 23), "6d 23h"),
    ])
    func formatRemainingFormatsDurations(seconds: Int, expected: String) {
        let resetAt = now.addingTimeInterval(TimeInterval(seconds))
        #expect(QuotaTitleFormatter.formatRemaining(resetAt, now: now) == expected)
    }

    @Test func formatRemainingClampsNegativeToZero() {
        let resetAt = now.addingTimeInterval(-3600)
        #expect(QuotaTitleFormatter.formatRemaining(resetAt, now: now) == "0m")
    }

    @Test func formatRemainingNilReturnsDash() {
        #expect(QuotaTitleFormatter.formatRemaining(nil, now: now) == "–m")
    }

    // MARK: - Multi-provider composer

    private var claude: ProviderUsage {
        ProviderUsage(
            currentPercent: 12, weeklyPercent: 76,
            currentResetAt: now.addingTimeInterval(60 * 135), updatedAt: now
        )
    }

    private var codex: ProviderUsage {
        ProviderUsage(
            currentPercent: 4, weeklyPercent: 30,
            weeklyResetAt: now.addingTimeInterval(60 * 60 * 24 * 3), updatedAt: now
        )
    }

    @Test func claudeModeRendersClaudeOnly() {
        let title = QuotaTitleFormatter.render(
            claude: claude, codex: codex, mode: .claude, now: now
        )
        #expect(title.string == "  12% 2h 15m  76%")
    }

    @Test func codexModeRendersCodexOnly() {
        let title = QuotaTitleFormatter.render(
            claude: claude, codex: codex, mode: .codex, now: now
        )
        #expect(title.string == "  4% –m  30% 3d")
    }

    @Test func bothModeJoinsStripsWithDotNoLabels() {
        let title = QuotaTitleFormatter.render(
            claude: claude, codex: codex, mode: .both, now: now
        )
        #expect(title.string == "  12% 2h 15m  76%  ·  4% –m  30% 3d")
    }
}
