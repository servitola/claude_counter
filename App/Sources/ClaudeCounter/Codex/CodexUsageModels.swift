import Foundation

/// Wire model for `GET https://chatgpt.com/backend-api/wham/usage`.
///
/// IMPORTANT: windows are classified by `limitWindowSeconds` (duration), NOT by
/// the primary/secondary label. Verified against a live Plus account, the sole
/// window can arrive as `primary_window` with a 7-day (`604800`) duration while
/// `secondary_window` is null — so a naive "primary == 5h" mapping is wrong.
/// `CodexUsageMapper` buckets each present window by its actual duration.
struct CodexUsageResponse: Decodable {
    let rateLimit: RateLimit?

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
    }

    struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?
        /// Model-specific extra windows; defaults to empty when the key is
        /// absent or null.
        let additionalRateLimits: [Window]

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
            case additionalRateLimits = "additional_rate_limits"
        }

        init(
            primaryWindow: Window?,
            secondaryWindow: Window?,
            additionalRateLimits: [Window] = []
        ) {
            self.primaryWindow = primaryWindow
            self.secondaryWindow = secondaryWindow
            self.additionalRateLimits = additionalRateLimits
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.primaryWindow = try container.decodeIfPresent(Window.self, forKey: .primaryWindow)
            self.secondaryWindow = try container.decodeIfPresent(
                Window.self,
                forKey: .secondaryWindow
            )
            self.additionalRateLimits = try container.decodeIfPresent(
                [Window].self, forKey: .additionalRateLimits
            ) ?? []
        }
    }

    struct Window: Decodable {
        /// Percent of the window consumed (0..100).
        let usedPercent: Double?
        /// Total window length in seconds — used to classify short vs weekly.
        let limitWindowSeconds: Int?
        /// Seconds until the window resets (relative to the response time).
        let resetAfterSeconds: Int?
        /// Absolute reset time as a Unix epoch (seconds).
        let resetAt: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case limitWindowSeconds = "limit_window_seconds"
            case resetAfterSeconds = "reset_after_seconds"
            case resetAt = "reset_at"
        }
    }
}
