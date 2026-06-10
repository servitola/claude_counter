import Foundation
import Testing
@testable import ClaudeCounter

struct QuotaParserTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func notFoundReturnsNil() {
        let payload = QuotaPayload(found: false)
        #expect(QuotaParser.parse(payload, now: now) == nil)
    }

    @Test func foundButEmptyYieldsNilFields() {
        let payload = QuotaPayload(found: true)
        let usage = QuotaParser.parse(payload, now: now)
        #expect(usage?.currentPercent == nil)
        #expect(usage?.weeklyPercent == nil)
        #expect(usage?.currentResetAt == nil)
        #expect(usage?.updatedAt == now)
    }

    @Test func textPercentsTakePrecedenceOverBars() {
        let payload = QuotaPayload(
            found: true,
            textPercents: [12.4, 76.9],
            barPercents: [99, 99]
        )
        let usage = QuotaParser.parse(payload, now: now)
        #expect(usage?.currentPercent == 12)
        #expect(usage?.weeklyPercent == 76)
    }

    @Test func barFallbacksUsedWhenTextEmpty() {
        let payload = QuotaPayload(
            found: true,
            textPercents: [],
            barPercents: [25, 33]
        )
        let usage = QuotaParser.parse(payload, now: now)
        #expect(usage?.currentPercent == 25)
        #expect(usage?.weeklyPercent == 33)
    }

    @Test func barFallbackForWeeklyOnlyWhenTextHasOne() {
        let payload = QuotaPayload(
            found: true,
            textPercents: [42],
            barPercents: [99, 88]
        )
        let usage = QuotaParser.parse(payload, now: now)
        #expect(usage?.currentPercent == 42)
        #expect(usage?.weeklyPercent == 88)
    }

    @Test func resetMinutesProjectedForward() {
        let payload = QuotaPayload(
            found: true,
            textPercents: [10],
            resetMinutes: 90
        )
        let usage = QuotaParser.parse(payload, now: now)
        #expect(usage?.currentResetAt == now.addingTimeInterval(60 * 90))
    }

    @Test func weeklyResetMinutesProjectedForward() {
        let payload = QuotaPayload(
            found: true,
            textPercents: [10, 32],
            weeklyResetMinutes: 551
        )
        let usage = QuotaParser.parse(payload, now: now)
        #expect(usage?.weeklyResetAt == now.addingTimeInterval(60 * 551))
    }

    @Test func percentsAreFloored() {
        let payload = QuotaPayload(
            found: true,
            textPercents: [99.99]
        )
        let usage = QuotaParser.parse(payload, now: now)
        #expect(usage?.currentPercent == 99)
    }
}
