import Foundation

/// Persists the user's provider display choice in `UserDefaults`. Mirrors the
/// injectable-defaults pattern of `OrgIDStore` so production uses `.standard`
/// while tests run against an isolated suite. `UserDefaults` is thread-safe but
/// not `Sendable`, hence `@unchecked Sendable`.
struct SettingsStore: @unchecked Sendable {
    /// Well-known key for the persisted display mode, namespaced to the app.
    static let displayModeKey = "display.mode"

    // Title-format keys (one per `TitleFormat` field, dotted-namespaced).
    static let presetKey = "format.preset"
    static let separatorKey = "format.separator"
    static let customTemplateKey = "format.customTemplate"
    static let customDriverKey = "format.customDriver"
    static let customTargetKey = "format.customTarget"
    static let customWarnKey = "format.customWarn"
    static let customAlertKey = "format.customAlert"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The persisted display mode, defaulting to `.both` when unset or invalid.
    func displayMode() -> ProviderDisplayMode {
        guard
            let raw = defaults.string(forKey: Self.displayModeKey),
            let mode = ProviderDisplayMode(rawValue: raw)
        else {
            return .both
        }
        return mode
    }

    /// Persist the chosen display mode.
    func setDisplayMode(_ mode: ProviderDisplayMode) {
        defaults.set(mode.rawValue, forKey: Self.displayModeKey)
    }

    /// The persisted title format. Any missing/invalid field falls back to the
    /// `TitleFormat()` default (preset `.full`, historic separator).
    func titleFormat() -> TitleFormat {
        let fallback = TitleFormat()
        let preset = defaults.string(forKey: Self.presetKey)
            .flatMap(TitlePreset.init(rawValue:)) ?? fallback.preset
        let separator = defaults.string(forKey: Self.separatorKey) ?? fallback.separator
        let template = defaults.string(forKey: Self.customTemplateKey) ?? fallback.customTemplate
        let driver = defaults.string(forKey: Self.customDriverKey)
            .flatMap(ColorDriver.init(rawValue:)) ?? fallback.customColorRule.driver
        let target = defaults.string(forKey: Self.customTargetKey)
            .flatMap(ColorTarget.init(rawValue:)) ?? fallback.customColorRule.target
        let warn = defaults.object(forKey: Self.customWarnKey) as? Int
            ?? fallback.customColorRule.warn
        let alert = defaults.object(forKey: Self.customAlertKey) as? Int
            ?? fallback.customColorRule.alert
        return TitleFormat(
            preset: preset,
            separator: separator,
            customTemplate: template,
            customColorRule: ColorRule(driver: driver, target: target, warn: warn, alert: alert)
        )
    }

    /// Persist the chosen title format.
    func setTitleFormat(_ format: TitleFormat) {
        defaults.set(format.preset.rawValue, forKey: Self.presetKey)
        defaults.set(format.separator, forKey: Self.separatorKey)
        defaults.set(format.customTemplate, forKey: Self.customTemplateKey)
        defaults.set(format.customColorRule.driver.rawValue, forKey: Self.customDriverKey)
        defaults.set(format.customColorRule.target.rawValue, forKey: Self.customTargetKey)
        defaults.set(format.customColorRule.warn, forKey: Self.customWarnKey)
        defaults.set(format.customColorRule.alert, forKey: Self.customAlertKey)
    }
}
