import Foundation

// MARK: - TitlePreset

/// A named menu-bar title format. Persisted via `SettingsStore` and mirrored
/// into `AppState.titleFormat`. `.full` reproduces the historic full strip;
/// the shorter presets and `.custom` render through the token template engine.
enum TitlePreset: String, CaseIterable, Sendable {
    /// Session %, its reset, and weekly % per provider (the historic default).
    case full
    /// Weekly % only.
    case weekly
    /// Session % and its reset only.
    case session
    /// Weekly % only, colored by the Claude session's urgency (70/92).
    case weeklyAlert
    /// A user-authored flat template.
    case custom

    /// Human-readable label for the settings picker.
    var title: String {
        switch self {
        case .full: "Full"
        case .weekly: "Weekly only"
        case .session: "Session only"
        case .weeklyAlert: "Weekly + session alert"
        case .custom: "Custom"
        }
    }
}

// MARK: - ColorDriver

/// What percentage decides a token's color.
enum ColorDriver: String, CaseIterable, Sendable {
    /// Each colored token is colored by its own provider's session %.
    case ownSession
    /// Every colored token is colored by Claude's session % (cross-signal).
    case claudeSession
    /// No coloring.
    case none
}

extension ColorDriver {
    /// Human-readable label for the settings picker.
    var title: String {
        switch self {
        case .ownSession: "Each provider's own session"
        case .claudeSession: "Claude's session"
        case .none: "No color"
        }
    }
}

// MARK: - ColorTarget

/// Which metric-token receives the color.
enum ColorTarget: String, CaseIterable, Sendable {
    case session
    case weekly
}

extension ColorTarget {
    /// Human-readable label for the settings picker.
    var title: String {
        switch self {
        case .session: "Session %"
        case .weekly: "Weekly %"
        }
    }
}

// MARK: - ColorRule

/// How the title's percentages are colored: a driver signal, a target token,
/// and the orange/red thresholds.
struct ColorRule: Equatable, Sendable {
    var driver: ColorDriver
    var target: ColorTarget
    var warn: Int
    var alert: Int

    /// Historic behavior: each provider's session %, orange@80/red@90.
    static let defaultSession = Self(
        driver: .ownSession, target: .session, warn: 80, alert: 90
    )
    /// Weekly numbers colored by Claude's 5-hour session, orange@70/red@92.
    static let weeklyAlert = Self(
        driver: .claudeSession, target: .weekly, warn: 70, alert: 92
    )
    /// Weekly-only preset: no coloring (thresholds unused).
    static let plainWeekly = Self(
        driver: .none, target: .weekly, warn: 80, alert: 90
    )
}

extension TitlePreset {
    /// The color rule baked into each built-in preset. `.custom` uses the
    /// user's own rule (see `TitleFormat.resolvedColorRule`).
    var presetColorRule: ColorRule {
        switch self {
        case .full, .session: .defaultSession
        case .weekly: .plainWeekly
        case .weeklyAlert: .weeklyAlert
        case .custom: .defaultSession
        }
    }
}

// MARK: - TitleFormat

/// The full menu-bar title configuration: the chosen preset, the separator used
/// when joining providers, and (for `.custom`) a raw template plus color rule.
/// A pure value type — the actual attributed-string rendering lives in
/// `QuotaTitleFormatter`.
struct TitleFormat: Equatable, Sendable {
    var preset: TitlePreset
    /// String placed between provider chips when generating a preset template.
    var separator: String
    /// User-authored flat template, authoritative when `preset == .custom`.
    var customTemplate: String
    /// Color rule used when `preset == .custom`.
    var customColorRule: ColorRule

    /// Two spaces, middle dot, two spaces — the historic visual gap.
    static let defaultSeparator = "  ·  "

    init(
        preset: TitlePreset = .full,
        separator: String = Self.defaultSeparator,
        customTemplate: String = "",
        customColorRule: ColorRule = .defaultSession
    ) {
        self.preset = preset
        self.separator = separator
        self.customTemplate = customTemplate
        self.customColorRule = customColorRule
    }

    /// The flat template to render for a given provider scope. `.custom` returns
    /// the user's raw template verbatim (scope is encoded in their tokens);
    /// every other preset generates one from its per-provider chip + separator.
    func resolvedTemplate(mode: ProviderDisplayMode) -> String {
        if preset == .custom {
            return customTemplate
        }
        let chips = providers(for: mode).map { provider in
            Self.chipTemplate(preset: preset, provider: provider)
        }
        return "  " + chips.joined(separator: separator)
    }

    /// The color rule to apply — the user's for `.custom`, else the preset's.
    var resolvedColorRule: ColorRule {
        preset == .custom ? customColorRule : preset.presetColorRule
    }

    /// The per-provider chip template for a preset, e.g. `{claude.weekly}`.
    /// Also used to seed a starting point when the user switches to `.custom`.
    static func chipTemplate(preset: TitlePreset, provider: String) -> String {
        switch preset {
        case .full: "{\(provider).session} {\(provider).session.reset}  {\(provider).weekly}"
        case .session: "{\(provider).session} {\(provider).session.reset}"
        case .weekly, .weeklyAlert, .custom: "{\(provider).weekly}"
        }
    }

    private func providers(for mode: ProviderDisplayMode) -> [String] {
        switch mode {
        case .claude: ["claude"]
        case .codex: ["codex"]
        case .both: ["claude", "codex"]
        }
    }
}
