import Foundation

/// Typed view over the loosely-typed JSON blob returned by the
/// extraction script. Construction validates and discards malformed
/// fields; the rest of the pipeline only deals with well-formed data.
struct QuotaPayload: Equatable {
    let found: Bool
    let textPercents: [Double]
    let barPercents: [Double]
    let resetMinutes: Int?
    let weeklyResetMinutes: Int?
    let matchedPattern: String?
    let matchedText: String?
    let raw: String

    init(
        found: Bool,
        textPercents: [Double] = [],
        barPercents: [Double] = [],
        resetMinutes: Int? = nil,
        weeklyResetMinutes: Int? = nil,
        matchedPattern: String? = nil,
        matchedText: String? = nil,
        raw: String = ""
    ) {
        self.found = found
        self.textPercents = textPercents
        self.barPercents = barPercents
        self.resetMinutes = resetMinutes
        self.weeklyResetMinutes = weeklyResetMinutes
        self.matchedPattern = matchedPattern
        self.matchedText = matchedText
        self.raw = raw
    }

    /// Build from the JS evaluation result. Returns nil only when the
    /// shape is wrong (not a dictionary). Missing fields are tolerated.
    init?(jsResult: Any?) {
        guard let dict = jsResult as? [String: Any] else { return nil }
        let found = (dict["found"] as? Bool) ?? false
        let textPcts = (dict["percentages"] as? [Double]) ?? []
        let barPcts = (dict["barPercents"] as? [Double]) ?? []
        func intField(_ key: String) -> Int? {
            if let asDouble = dict[key] as? Double {
                return Int(asDouble)
            }
            if let asInt = dict[key] as? Int {
                return asInt
            }
            return nil
        }
        let mins = intField("resetMinutes")
        let weeklyMins = intField("weeklyResetMinutes")
        let pattern: String? = {
            if let str = dict["matchedPattern"] as? String {
                return str
            }
            if let int = dict["matchedPattern"] as? Int {
                return String(int)
            }
            return nil
        }()
        let raw = (dict["raw"] as? String) ?? ""
        self.init(
            found: found,
            textPercents: textPcts,
            barPercents: barPcts,
            resetMinutes: mins,
            weeklyResetMinutes: weeklyMins,
            matchedPattern: pattern,
            matchedText: dict["matchedText"] as? String,
            raw: raw
        )
    }
}
