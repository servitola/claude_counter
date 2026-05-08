import Foundation
import Testing
@testable import ClaudeCounter

/// Drives `QuotaScraper.parserLibraryJS` against fixture strings that
/// approximate the aggregated text claude.ai/settings/usage emits.
/// When claude.ai changes its markup, capture the new aggregate from
/// `/tmp/claude_counter_debug.txt`, drop it in here, and update the
/// expectations.
struct JSQuotaParserTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Percentages

    @Test func parsesSinglePercentage() {
        let payload = JSQuotaParserHarness.parse(
            text: "Some preamble | 12% used | more text",
            now: now
        )
        #expect(payload?.found == true)
        #expect(payload?.textPercents == [12])
        #expect(payload?.resetMinutes == nil)
    }

    @Test func parsesCurrentAndWeeklyPercentages() {
        let payload = JSQuotaParserHarness.parse(
            text: "Current 5h | 12% used | Weekly | 76% used | Resets in 2h 15m",
            now: now
        )
        #expect(payload?.textPercents == [12, 76])
        #expect(payload?.resetMinutes == 135)
    }

    @Test func parsesDecimalPercentages() {
        let payload = JSQuotaParserHarness.parse(text: "0.5% used | 99.7% used", now: now)
        #expect(payload?.textPercents == [0.5, 99.7])
    }

    // MARK: - Reset patterns

    @Test(arguments: [
        ("Resets in 2h 15m", 135),
        ("Resets in 3h", 180),
        ("Resets in 45m", 45),
        ("Resets in about 5 hours", 300),
        ("Resets in about 12 minutes", 12),
        ("3 hours and 12 minutes left", 192),
        ("47 minutes remaining", 47),
        ("4 hours left", 240),
        // Variants observed live on claude.ai 2026-05.
        ("Resets in 4 hr 17 min", 257),
        ("Resets in 1 hr", 60),
        ("Resets in 30 min", 30),
    ])
    func parsesRelativeResets(text: String, expectedMinutes: Int) {
        let payload = JSQuotaParserHarness.parse(text: "5% used | \(text)", now: now)
        #expect(payload?.resetMinutes == expectedMinutes)
        #expect(payload?.matchedText.map(\.isEmpty) == false)
    }

    @Test func parsesAbsoluteResetTimePM() {
        // now = 1_700_000_000 → 2023-11-14 22:13:20 UTC.
        // Locally (varies by host) we just check it landed in [0, 24h).
        let payload = JSQuotaParserHarness.parse(text: "5% used | Resets at 9:30 PM", now: now)
        #expect(payload?.resetMinutes != nil)
        let minutes = payload?.resetMinutes ?? -1
        #expect(minutes >= 0 && minutes < 24 * 60)
        #expect(payload?.matchedPattern == "absolute")
    }

    @Test func absoluteTimeRollsOverWhenInPast() {
        // "Resets at 1:00 AM" — should always project forward.
        let payload = JSQuotaParserHarness.parse(text: "5% used | Resets at 1:00 AM", now: now)
        let minutes = payload?.resetMinutes ?? -1
        #expect(minutes >= 0 && minutes <= 24 * 60)
    }

    // MARK: - Bar fallbacks

    @Test func barPercentsAlone() {
        let payload = JSQuotaParserHarness.parse(text: "no useful text", barPercents: [42, 88])
        #expect(payload?.found == true)
        #expect(payload?.textPercents.isEmpty == true)
        #expect(payload?.barPercents == [42, 88])
    }

    @Test func textPercentsAndBarsCoexist() {
        let payload = JSQuotaParserHarness.parse(
            text: "12% used | 76% used",
            barPercents: [12, 76]
        )
        #expect(payload?.textPercents == [12, 76])
        #expect(payload?.barPercents == [12, 76])
    }

    // MARK: - Found / not-found

    @Test func emptyTextWithNoBarsIsNotFound() {
        let payload = JSQuotaParserHarness.parse(text: "")
        #expect(payload?.found == false)
        #expect(payload?.textPercents.isEmpty == true)
        #expect(payload?.barPercents.isEmpty == true)
        #expect(payload?.resetMinutes == nil)
    }

    @Test func unrelatedTextIsNotFound() {
        let payload = JSQuotaParserHarness.parse(text: "claude.ai | Settings | Usage")
        #expect(payload?.found == false)
    }

    // MARK: - Realistic full snapshots

    // These approximate the full aggregated text the scraper sees on
    // claude.ai/settings/usage. Update from /tmp/claude_counter_debug.txt
    // when the page changes.

    @Test func realisticLowUsage() {
        let text = """
        Claude | Usage | Current 5-hour session | 12% used | Resets in 2h 15m | \
        Weekly | 76% used | Plan: Max | Manage subscription
        """
        let payload = JSQuotaParserHarness.parse(text: text, now: now)
        #expect(payload?.found == true)
        #expect(payload?.textPercents == [12, 76])
        #expect(payload?.resetMinutes == 135)
        #expect(payload?.matchedPattern == "0")
    }

    @Test func realisticNearLimit() {
        let text = """
        Usage | Current 5-hour session | 93% used | Resets in 12 minutes | \
        Weekly | 88% used | Approaching limits
        """
        let payload = JSQuotaParserHarness.parse(text: text, now: now)
        #expect(payload?.textPercents == [93, 88])
        #expect(payload?.resetMinutes == 12)
        #expect(payload?.matchedPattern == "2")
    }

    @Test func realisticBarFallbackOnly() {
        // claude.ai briefly served progress bars without text labels.
        // Text has no "% used" matches; bars carry the values.
        let text = "Usage | Current session | Weekly | Reload"
        let payload = JSQuotaParserHarness.parse(
            text: text,
            barPercents: [25, 50],
            now: now
        )
        #expect(payload?.found == true)
        #expect(payload?.textPercents.isEmpty == true)
        #expect(payload?.barPercents == [25, 50])
        #expect(payload?.resetMinutes == nil)
    }
}
