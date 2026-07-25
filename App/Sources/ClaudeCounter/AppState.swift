import Foundation
import Observation

/// Single source of truth for usage data shared across status bar + windows.
@MainActor
@Observable
final class AppState {
    /// Claude usage (scraped from claude.ai).
    var usage: ClaudeUsage = .empty
    /// Codex usage (read from the OpenAI backend via the local Codex CLI token).
    var codex: ProviderUsage = .empty
    /// Codex fetch state — distinguishes "loading", "ok", and "log in via codex
    /// CLI" for the overview window.
    var codexStatus: ProviderStatus = .loading
    /// Which provider(s) the menu-bar strip shows. Loaded from `SettingsStore`
    /// at launch, updated live from the settings window.
    var displayMode: ProviderDisplayMode = .both
    /// How the menu-bar strip is formatted + colored. Loaded from
    /// `SettingsStore` at launch, updated live from the settings window.
    var titleFormat = TitleFormat()
}
