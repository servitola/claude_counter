import AppKit

/// The token-template rendering path. `.full` stays on the historic per-provider
/// renderer (see `QuotaTitleFormatter`); every shorter preset and `.custom`
/// substitutes `{provider.metric}` tokens in a flat template and applies a
/// `ColorRule`.
extension QuotaTitleFormatter {
    /// Compose the menu-bar strip for the selected provider(s) and format.
    /// `.full` delegates to the historic renderer (which omits windows a provider
    /// lacks); other presets render through the token engine.
    static func render(
        claude: ProviderUsage,
        codex: ProviderUsage,
        mode: ProviderDisplayMode,
        format: TitleFormat,
        now: Date = Date()
    )
        -> NSAttributedString
    {
        if format.preset == .full {
            return render(claude: claude, codex: codex, mode: mode, now: now)
        }
        return renderTemplate(
            format.resolvedTemplate(mode: mode),
            colorRule: format.resolvedColorRule,
            claude: claude,
            codex: codex,
            now: now
        )
    }

    private enum TokenProvider { case claude, codex }
    private enum TokenMetric { case session, weekly, sessionReset, weeklyReset }
    private struct TokenKind {
        let provider: TokenProvider
        let metric: TokenMetric
    }

    /// Render a flat template ("  {claude.weekly}  ·  {codex.weekly}") against
    /// both snapshots. Literal text passes through verbatim; recognized
    /// `{provider.metric}` tokens are substituted (nil data → "–%" / "–m") and
    /// then colored per `rule`. Unknown tokens are left as literal text so the
    /// user notices a typo.
    private static func renderTemplate(
        _ template: String,
        colorRule rule: ColorRule,
        claude: ProviderUsage,
        codex: ProviderUsage,
        now: Date
    )
        -> NSAttributedString
    {
        let result = NSMutableAttributedString()
        var spans: [(range: NSRange, kind: TokenKind)] = []
        var literal = ""
        func flush() {
            if !literal.isEmpty {
                result.append(NSAttributedString(string: literal))
                literal = ""
            }
        }

        let chars = Array(template)
        var idx = 0
        while idx < chars.count {
            if
                chars[idx] == "{",
                let close = chars[(idx + 1)...].firstIndex(of: "}"),
                let kind = parseToken(String(chars[(idx + 1) ..< close]))
            {
                flush()
                let value = tokenValue(kind, claude: claude, codex: codex, now: now)
                let start = result.length
                result.append(NSAttributedString(string: value))
                spans.append((NSRange(location: start, length: value.utf16.count), kind))
                idx = close + 1
            } else {
                literal.append(chars[idx])
                idx += 1
            }
        }
        flush()

        applyColor(rule, to: result, spans: spans, claude: claude, codex: codex)
        return result
    }

    private static func applyColor(
        _ rule: ColorRule,
        to result: NSMutableAttributedString,
        spans: [(range: NSRange, kind: TokenKind)],
        claude: ProviderUsage,
        codex: ProviderUsage
    ) {
        guard rule.driver != .none else { return }
        for span in spans where matches(span.kind.metric, rule.target) {
            guard
                let pct = driverPercent(rule.driver, kind: span.kind, claude: claude, codex: codex),
                let color = colorFor(pct, warn: rule.warn, alert: rule.alert)
            else { continue }
            result.addAttribute(.foregroundColor, value: color, range: span.range)
        }
    }

    private static func driverPercent(
        _ driver: ColorDriver,
        kind: TokenKind,
        claude: ProviderUsage,
        codex: ProviderUsage
    )
        -> Int?
    {
        switch driver {
        case .claudeSession:
            claude.currentPercent

        case .ownSession:
            kind.provider == .claude ? claude.currentPercent : codex.currentPercent

        case .none:
            nil
        }
    }

    private static func matches(_ metric: TokenMetric, _ target: ColorTarget) -> Bool {
        switch target {
        case .session: metric == .session
        case .weekly: metric == .weekly
        }
    }

    private static func colorFor(_ pct: Int, warn: Int, alert: Int) -> NSColor? {
        if pct >= alert {
            return .systemRed
        }
        if pct >= warn {
            return .systemOrange
        }
        return nil
    }

    private static func parseToken(_ name: String) -> TokenKind? {
        switch name {
        case "claude.session": TokenKind(provider: .claude, metric: .session)
        case "claude.weekly": TokenKind(provider: .claude, metric: .weekly)
        case "claude.session.reset": TokenKind(provider: .claude, metric: .sessionReset)
        case "claude.weekly.reset": TokenKind(provider: .claude, metric: .weeklyReset)
        case "codex.session": TokenKind(provider: .codex, metric: .session)
        case "codex.weekly": TokenKind(provider: .codex, metric: .weekly)
        case "codex.session.reset": TokenKind(provider: .codex, metric: .sessionReset)
        case "codex.weekly.reset": TokenKind(provider: .codex, metric: .weeklyReset)
        default: nil
        }
    }

    private static func tokenValue(
        _ kind: TokenKind,
        claude: ProviderUsage,
        codex: ProviderUsage,
        now: Date
    )
        -> String
    {
        let usage = kind.provider == .claude ? claude : codex
        switch kind.metric {
        case .session: return usage.currentPercent.map { "\($0)%" } ?? "–%"
        case .weekly: return usage.weeklyPercent.map { "\($0)%" } ?? "–%"
        case .sessionReset: return formatRemaining(usage.currentResetAt, now: now)
        case .weeklyReset: return formatRemaining(usage.weeklyResetAt, now: now)
        }
    }
}
