import Foundation
import Testing
@testable import ClaudeCounter

struct ScrapeDebugFormatTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func formatsPopulatedPayload() {
        let payload = QuotaPayload(
            found: true,
            textPercents: [12, 76],
            barPercents: [25, 50],
            resetMinutes: 135,
            matchedPattern: "0",
            matchedText: "Resets in 2h 15m",
            raw: "raw page text"
        )
        let out = QuotaScraper.formatDebug(payload, now: now)
        #expect(out.contains("percentages: [12.0, 76.0]"))
        #expect(out.contains("barPercents: [25.0, 50.0]"))
        #expect(out.contains("resetMinutes: 135"))
        #expect(out.contains("matchedPattern: 0"))
        #expect(out.contains("matchedText: Resets in 2h 15m"))
        #expect(out.contains("raw page text"))
    }

    @Test func formatsMissingFieldsAsNilPlaceholders() {
        let payload = QuotaPayload(found: false)
        let out = QuotaScraper.formatDebug(payload, now: now)
        #expect(out.contains("resetMinutes: nil"))
        #expect(out.contains("matchedPattern: nil"))
        #expect(out.contains("matchedText: (no match)"))
    }

    @Test func truncatesRawTo2000Chars() {
        let huge = String(repeating: "x", count: 5000)
        let payload = QuotaPayload(found: true, raw: huge)
        let out = QuotaScraper.formatDebug(payload, now: now)
        let header = "--- raw aggregated text (first 2000 chars) ---\n"
        guard let range = out.range(of: header) else {
            Issue.record("header not present")
            return
        }
        let body = out[range.upperBound...]
        #expect(body.count <= 2000)
    }
}
