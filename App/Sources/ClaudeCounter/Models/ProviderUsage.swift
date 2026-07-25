import Foundation

// MARK: - ProviderUsage

/// Snapshot of one provider's usage: a short ("current", ~5h) window and a
/// weekly window, each a percent-used plus a wall-clock reset time. Shared by
/// both providers — Claude (scraped from claude.ai) and Codex (read from the
/// OpenAI backend via the local `~/.codex/auth.json` token).
struct ProviderUsage: Equatable {
    /// Current short-window % (0..100). Nil until the first successful fetch.
    var currentPercent: Int?
    /// Weekly % (0..100). Nil until the first successful fetch.
    var weeklyPercent: Int?
    /// Wall-clock time when the current window resets.
    /// Stored as a Date so the menu-bar countdown ticks down without a
    /// fresh fetch — the formatter recomputes minutes-remaining on
    /// each render.
    var currentResetAt: Date?
    /// Wall-clock time when the weekly limit resets (typically 7 days rolling).
    var weeklyResetAt: Date?
    /// When this snapshot was produced.
    var updatedAt: Date?

    static let empty = Self()

    var isLoaded: Bool {
        currentPercent != nil || weeklyPercent != nil
    }
}

/// Back-compat alias: the Claude scraping path and its tests predate the
/// multi-provider generalization and still refer to `ClaudeUsage`.
typealias ClaudeUsage = ProviderUsage
