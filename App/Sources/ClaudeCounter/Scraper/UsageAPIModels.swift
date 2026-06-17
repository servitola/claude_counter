import Foundation

// MARK: - UsageAPIModels

/// `Decodable` models for claude.ai's internal usage endpoints plus a
/// configured `JSONDecoder`.
///
/// Two endpoints feed the scraper:
/// - `GET /api/organizations` → `[OrgSummary]`
/// - `GET /api/organizations/{uuid}/usage` → `UsageResponse`
///
/// This file is the sole definition site for `OrgSummary`, `UsageLimit`,
/// `FlatWindow`, and `UsageResponse`; downstream tasks reuse these types
/// rather than redeclaring them.
enum UsageAPIModels {
    /// A `JSONDecoder` configured with the two-formatter ISO-8601 strategy.
    ///
    /// Returns a fresh instance per call: `JSONDecoder` is not `Sendable`,
    /// and the custom date strategy builds its own formatters, so no shared
    /// mutable state crosses concurrency domains.
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(decodeISO8601Date)
        return decoder
    }

    /// Try a fractional-seconds ISO-8601 parse first, then fall back to one
    /// without fractional seconds. `ISO8601DateFormatter` is not meant to
    /// have its options toggled between calls, so two separate instances are
    /// used; they are created locally because the type is not `Sendable`.
    private static func decodeISO8601Date(_ decoder: any Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: raw) {
            return date
        }

        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.formatOptions = [.withInternetDateTime]
        if let date = plainFormatter.date(from: raw) {
            return date
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid ISO-8601 date: \(raw)"
            )
        )
    }
}

// MARK: - OrgSummary

/// One organization from `GET /api/organizations`. Only `uuid` is needed;
/// other fields (`id`, `name`, `settings`, …) are ignored.
struct OrgSummary: Decodable {
    let uuid: String
}

// MARK: - UsageLimit

/// One entry from `UsageResponse.limits`. This is the canonical,
/// self-describing usage source (session vs weekly_all vs weekly_scoped).
/// `scope` and other extra keys are ignored.
struct UsageLimit: Decodable {
    let group: String
    let kind: String
    /// JSON sends an integer (e.g. `3`); decoded as `Double`.
    let percent: Double
    let resetsAt: Date?
    // `is_active` may be absent in some responses, so it is modelled as an
    // optional Bool per the API contract.
    // swiftlint:disable:next discouraged_optional_boolean
    let isActive: Bool?

    private enum CodingKeys: String, CodingKey {
        case group
        case kind
        case percent
        case resetsAt = "resets_at"
        case isActive = "is_active"
    }
}

// MARK: - FlatWindow

/// A flat usage window (`five_hour` / `seven_day`) of the form
/// `{ "resets_at": ..., "utilization": <int> }`. Used as a fallback when
/// `limits[]` is empty or incomplete.
struct FlatWindow: Decodable {
    let resetsAt: Date?
    /// JSON sends an integer (e.g. `51`); decoded as `Double`.
    let utilization: Double

    private enum CodingKeys: String, CodingKey {
        case resetsAt = "resets_at"
        case utilization
    }
}

// MARK: - UsageResponse

/// Response from `GET /api/organizations/{uuid}/usage`. Owns `limits[]`
/// plus the optional flat windows. Extra top-level keys (`spend`,
/// `extra_usage`, `seven_day_sonnet`, …) are ignored.
struct UsageResponse: Decodable {
    let limits: [UsageLimit]
    let fiveHour: FlatWindow?
    let sevenDay: FlatWindow?

    private enum CodingKeys: String, CodingKey {
        case limits
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}
