import AppKit
import Testing
@testable import ClaudeCounter

/// Tests for the token-template rendering path (shorter presets + `.custom`),
/// kept separate from the legacy-renderer tests to stay under the type-body
/// length limit.
@MainActor
struct QuotaTitleFormatterTemplateTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

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

    // MARK: - Template presets

    @Test func fullPresetMatchesLegacyRenderer() {
        let legacy = QuotaTitleFormatter.render(
            claude: claude, codex: codex, mode: .both, now: now
        )
        let full = QuotaTitleFormatter.render(
            claude: claude, codex: codex, mode: .both,
            format: TitleFormat(preset: .full), now: now
        )
        #expect(full.string == legacy.string)
    }

    @Test func weeklyPresetShowsOnlyWeeklyPercents() {
        let title = QuotaTitleFormatter.render(
            claude: claude, codex: codex, mode: .both,
            format: TitleFormat(preset: .weekly), now: now
        )
        #expect(title.string == "  76%  ·  30%")
    }

    @Test func templateNilTokenRendersDash() {
        let title = QuotaTitleFormatter.render(
            claude: .empty, codex: .empty, mode: .claude,
            format: TitleFormat(preset: .weekly), now: now
        )
        #expect(title.string == "  –%")
    }

    @Test func customTemplateRendersLiteralTextAndTokens() {
        let format = TitleFormat(preset: .custom, customTemplate: "C{claude.weekly}")
        let title = QuotaTitleFormatter.render(
            claude: claude, codex: codex, mode: .both, format: format, now: now
        )
        #expect(title.string == "C76%")
    }

    @Test func unknownTokenLeftLiteral() {
        let format = TitleFormat(preset: .custom, customTemplate: "{bogus}{claude.weekly}")
        let title = QuotaTitleFormatter.render(
            claude: claude, codex: codex, mode: .both, format: format, now: now
        )
        #expect(title.string == "{bogus}76%")
    }

    // MARK: - Weekly + session alert coloring

    /// Claude session ≥ 92 → BOTH weekly numbers red, driven by Claude's session.
    @Test func weeklyAlertColorsBothWeeklyRedByClaudeSession() {
        let hotClaude = ProviderUsage(currentPercent: 92, weeklyPercent: 40, updatedAt: now)
        let cool = ProviderUsage(currentPercent: 3, weeklyPercent: 20, updatedAt: now)
        let title = QuotaTitleFormatter.render(
            claude: hotClaude, codex: cool, mode: .both,
            format: TitleFormat(preset: .weeklyAlert), now: now
        )
        // "  40%  ·  20%" — claude weekly at index 2, codex weekly at index 10.
        #expect(title.string == "  40%  ·  20%")
        let claudeColor = title.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
        let codexColor = title.attribute(.foregroundColor, at: 10, effectiveRange: nil) as? NSColor
        #expect(claudeColor == .systemRed)
        #expect(codexColor == .systemRed)
    }

    @Test func weeklyAlertOrangeWhenClaudeSessionAtSeventy() {
        let claudeSession70 = ProviderUsage(currentPercent: 70, weeklyPercent: 40, updatedAt: now)
        let title = QuotaTitleFormatter.render(
            claude: claudeSession70, codex: .empty, mode: .claude,
            format: TitleFormat(preset: .weeklyAlert), now: now
        )
        let color = title.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
        #expect(color == .systemOrange)
    }

    @Test func weeklyAlertNoColorBelowSeventy() {
        let claudeSession69 = ProviderUsage(currentPercent: 69, weeklyPercent: 40, updatedAt: now)
        let title = QuotaTitleFormatter.render(
            claude: claudeSession69, codex: .empty, mode: .claude,
            format: TitleFormat(preset: .weeklyAlert), now: now
        )
        let color = title.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
        #expect(color == nil)
    }
}
