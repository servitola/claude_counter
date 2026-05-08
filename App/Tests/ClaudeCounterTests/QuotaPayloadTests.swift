import Foundation
import Testing
@testable import ClaudeCounter

struct QuotaPayloadTests {
    @Test func nonDictionaryReturnsNil() {
        #expect(QuotaPayload(jsResult: 42) == nil)
        #expect(QuotaPayload(jsResult: "string") == nil)
        #expect(QuotaPayload(jsResult: nil) == nil)
    }

    @Test func emptyDictionaryParsesAsNotFound() {
        let payload = QuotaPayload(jsResult: [String: Any]())
        #expect(payload?.found == false)
        #expect(payload?.textPercents.isEmpty == true)
        #expect(payload?.barPercents.isEmpty == true)
        #expect(payload?.resetMinutes == nil)
        #expect(payload?.matchedPattern == nil)
        #expect(payload?.matchedText == nil)
        #expect(payload?.raw.isEmpty == true)
    }

    @Test func fullPayloadRoundTrips() {
        let payload = QuotaPayload(jsResult: [
            "found": true,
            "percentages": [12.0, 76.0],
            "barPercents": [25.0, 50.0],
            "resetMinutes": 135.0,
            "matchedPattern": 0,
            "matchedText": "Resets in 2h 15m",
            "raw": "page text"
        ] as [String: Any])
        #expect(payload?.found == true)
        #expect(payload?.textPercents == [12.0, 76.0])
        #expect(payload?.barPercents == [25.0, 50.0])
        #expect(payload?.resetMinutes == 135)
        #expect(payload?.matchedPattern == "0")
        #expect(payload?.matchedText == "Resets in 2h 15m")
        #expect(payload?.raw == "page text")
    }

    @Test func resetMinutesAcceptsIntOrDouble() {
        let payloadDouble = QuotaPayload(jsResult: [
            "found": true,
            "resetMinutes": 90.7
        ] as [String: Any])
        let payloadInt = QuotaPayload(jsResult: [
            "found": true,
            "resetMinutes": 90
        ] as [String: Any])
        #expect(payloadDouble?.resetMinutes == 90)
        #expect(payloadInt?.resetMinutes == 90)
    }

    @Test func matchedPatternAcceptsString() {
        let payload = QuotaPayload(jsResult: [
            "found": true,
            "matchedPattern": "absolute"
        ] as [String: Any])
        #expect(payload?.matchedPattern == "absolute")
    }
}
