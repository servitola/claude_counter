import Foundation

// MARK: - ProviderDisplayMode

/// Which provider(s) the menu-bar strip shows. Persisted via `SettingsStore`
/// and mirrored into `AppState.displayMode` for reactive rendering.
enum ProviderDisplayMode: String, CaseIterable, Sendable {
    case claude
    case codex
    case both

    /// Human-readable label for the settings picker.
    var title: String {
        switch self {
        case .claude: "Claude only"
        case .codex: "Codex only"
        case .both: "Both"
        }
    }
}

// MARK: - ProviderStatus

/// Fetch state for a provider whose auth can lapse (currently only Codex, which
/// depends on `~/.codex/auth.json`). Drives the overview window's hint text.
enum ProviderStatus: Sendable, Equatable {
    /// No successful fetch yet this launch.
    case loading
    /// Last fetch succeeded.
    case ok
    /// No local token, or the backend rejected it (401/403) — user must run
    /// `codex login` in the CLI.
    case needsAuth
    /// A transient/decode error; the last known snapshot (if any) is retained.
    case error
}
