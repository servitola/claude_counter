import Foundation

/// Snapshot of Claude usage scraped from claude.ai/settings/usage.
struct ClaudeUsage: Equatable {
    /// Current 5h-window % (0..100). Nil until first successful scrape.
    var currentPercent: Int?
    /// Weekly % (0..100). Nil until first successful scrape.
    var weeklyPercent: Int?
    /// Wall-clock time when current 5h window resets.
    /// Stored as a Date so the menu-bar countdown ticks down without a
    /// fresh scrape — the formatter recomputes minutes-remaining on
    /// each render.
    var currentResetAt: Date?
    /// When this snapshot was produced.
    var updatedAt: Date?

    static let empty = Self()

    var isLoaded: Bool {
        currentPercent != nil || weeklyPercent != nil
    }
}
