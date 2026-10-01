public import Foundation

/// The usage JSON the app publishes, read back: `StatusExport` schema v2. The
/// top-level fields are Claude, `codex` holds the same for Codex, and a field
/// that is not known yet is absent.
public struct UsageSnapshot: Decodable, Equatable, Sendable {
    public struct Provider: Decodable, Equatable, Sendable {
        public var currentPercent: Int?
        public var weeklyPercent: Int?
        public var currentResetAt: Date?
        public var weeklyResetAt: Date?

        public var isLoaded: Bool {
            currentPercent != nil || weeklyPercent != nil
        }

        public init(
            currentPercent: Int? = nil,
            weeklyPercent: Int? = nil,
            currentResetAt: Date? = nil,
            weeklyResetAt: Date? = nil
        ) {
            self.currentPercent = currentPercent
            self.weeklyPercent = weeklyPercent
            self.currentResetAt = currentResetAt
            self.weeklyResetAt = weeklyResetAt
        }
    }

    public var claude: Provider
    public var codex: Provider
    public var updatedAt: Date

    public init(claude: Provider, codex: Provider, updatedAt: Date) {
        self.claude = claude
        self.codex = codex
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case updatedAt, codex
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.claude = try Provider(from: decoder)
        self.codex = try container.decodeIfPresent(Provider.self, forKey: .codex) ?? Provider()
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: data)
    }
}
